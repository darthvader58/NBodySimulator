#include <metal_stdlib>
using namespace metal;

struct Body {
    float2 position;
    float2 velocity;
    float mass;
    float3 color;
    float _pad;
};

kernel void computeForces(
    device Body* bodies [[buffer(0)]],
    constant uint& numBodies [[buffer(1)]],
    constant float& deltaTime [[buffer(2)]],
    constant float& softening [[buffer(3)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= numBodies) return;
    
    Body body = bodies[gid];
    float2 force = float2(0.0);
    
    for (uint i = 0; i < numBodies; i++) {
        if (i == gid) continue;
        
        Body other = bodies[i];
        float2 direction = other.position - body.position;
        float distSq = dot(direction, direction) + softening;
        float dist = sqrt(distSq);
        
        float forceMag = (body.mass * other.mass) / distSq;
        force += normalize(direction) * forceMag;
    }
    
    float2 accel = force / body.mass;
    body.velocity += accel * deltaTime;
    body.velocity *= 0.9999; // Damping
    
    bodies[gid] = body;
}

kernel void updatePositions(
    device Body* bodies [[buffer(0)]],
    constant uint& numBodies [[buffer(1)]],
    constant float& deltaTime [[buffer(2)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= numBodies) return;
    
    Body body = bodies[gid];
    body.position += body.velocity * deltaTime;
    
    // Toroidal wrapping
    if (body.position.x < -1.0) body.position.x += 2.0;
    if (body.position.x > 1.0) body.position.x -= 2.0;
    if (body.position.y < -1.0) body.position.y += 2.0;
    if (body.position.y > 1.0) body.position.y -= 2.0;
    
    bodies[gid] = body;
}

kernel void renderBodies(
    texture2d<float, access::write> output [[texture(0)]],
    device const Body* bodies [[buffer(0)]],
    constant uint& numBodies [[buffer(1)]],
    constant float& particleSize [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]])
{
    uint width = output.get_width();
    uint height = output.get_height();
    
    if (gid.x >= width || gid.y >= height) return;
    
    float aspectRatio = float(width) / float(height);
    float2 pixelPos = float2(gid) / float2(width, height);
    pixelPos = (pixelPos - 0.5) * 2.0;
    pixelPos.x *= aspectRatio;
    
    float3 color = float3(0.0);
    
    for (uint i = 0; i < numBodies; i++) {
        Body body = bodies[i];
        float2 bodyPos = body.position;
        bodyPos.x *= aspectRatio;
        
        float dist = length(pixelPos - bodyPos);
        float size = particleSize * sqrt(body.mass);
        
        float intensity = smoothstep(size * 2.0, 0.0, dist);
        intensity *= intensity;
        
        color += body.color * intensity * body.mass * 5.0;
    }
    
    // Background stars
    uint hash = gid.x * 73856093 ^ gid.y * 19349663;
    float star = float(hash % 10000) / 10000.0;
    if (star > 0.998) {
        color += float3(0.5);
    }
    
    output.write(float4(color, 1.0), gid);
}

kernel void clearTexture(
    texture2d<float, access::write> output [[texture(0)]],
    constant float4& clearColor [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    uint width = output.get_width();
    uint height = output.get_height();
    
    if (gid.x >= width || gid.y >= height) return;
    
    // Fade previous frame for trails
    float4 prev = output.read(gid);
    float4 faded = prev * 0.95 + clearColor * 0.05;
    output.write(faded, gid);
}
