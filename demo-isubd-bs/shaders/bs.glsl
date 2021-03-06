#line 1
////////////////////////////////////////////////////////////////////////////////
// Implicit Subdivition Sahder for Terrain Rendering
//

layout (std430, binding = BUFFER_BINDING_SUBD1)
readonly buffer SubdBufferIn {
    uvec2 u_SubdBufferIn[];
};

layout (std430, binding = BUFFER_BINDING_SUBD2)
buffer SubdBufferOut {
    uvec2 u_SubdBufferOut[];
};

layout (std430, binding = BUFFER_BINDING_PATCH)
readonly buffer VertexBuffer {
    vec4 u_VertexBuffer[];
};

layout (binding = BUFFER_BINDING_SUBD_COUNTER)
uniform atomic_uint u_SubdBufferCounter;

uniform float u_LodFactor = 1.0;

float distanceToLod(float z, float lodFactor)
{
    return -log2(clamp(z * lodFactor, 0.0f, 1.0f));
}

float computeLod(vec3 c)
{
    vec3 cxf = c.xyz;
    float z = length(cxf);

    return distanceToLod(z, u_LodFactor);
}

float computeLod(in vec4 v[4])
{
    vec3 c = (v[0].xyz + v[1].xyz + v[2].xyz + v[3].xyz) / 4.0;
    return computeLod(c);
}

// -----------------------------------------------------------------------------
/**
 * Vertex Shader
 *
 * The vertex shader is empty
 */
#ifdef VERTEX_SHADER
void main()
{ }
#endif

// -----------------------------------------------------------------------------
/**
 * Tessellation Control Shader
 *
 * This tessellaction control shader is responsible for updating the
 * subdivision buffer and sending visible geometry to the rasterizer.
 */
#ifdef TESS_CONTROL_SHADER
layout (vertices = 1) out;
out Patch {
    vec4 vertices[4];
    float u[2];
} o_Patch[];

void writeKey(uint primID, uint key)
{
    uint idx = atomicCounterIncrement(u_SubdBufferCounter);

    u_SubdBufferOut[idx] = uvec2(primID, key);
}

void updateSubdBuffer(uint primID, uint key, int targetLod, int parentLod)
{
    // extract subdivision level associated to the key
    int keyLod = findMSB(key) / 2;

    // update the key accordingly
    if (/* subdivide ? */ keyLod < targetLod && !isLeafKey(key)) {
        uint children[4]; childrenKeys(key, children);

        writeKey(primID, children[0]);
        writeKey(primID, children[1]);
        writeKey(primID, children[2]);
        writeKey(primID, children[3]);
    } else if (/* keep ? */ keyLod < (parentLod + 1)) {
        writeKey(primID, key);
    } else /* merge ? */ {
        if (/* is root ? */isRootKey(key)) {
            writeKey(primID, key);
        } else if (/* is zero child ? */isChildZeroKey(key)) {
            writeKey(primID, parentKey(key));
        }
    }
}

void main()
{
    // get threadID (each key is associated to a thread)
    int threadID = gl_PrimitiveID;

    // get coarse line associated to the key
    uint primID = u_SubdBufferIn[threadID].x;
    vec4 v_in[4] = vec4[4](
        u_VertexBuffer[0],
        u_VertexBuffer[1],
        u_VertexBuffer[2],
        u_VertexBuffer[3]
    );

    // compute distance-based LOD
    uint key = u_SubdBufferIn[threadID].y;
    vec4 v[4], vp[4]; float u[2]; subd(key, v_in, v, vp, u);
    int targetLod = int(computeLod(v));
    int parentLod = int(computeLod(vp));
#if FLAG_FREEZE
    parentLod = targetLod = findMSB(key) / 2;
#endif
#if FLAG_UNIFORM
    parentLod = targetLod = UNIFORM_SUBD_FACTOR;
#endif
    updateSubdBuffer(primID, key, targetLod, parentLod);

    if (true) {
        // set tess levels
        int tessLevel = PATCH_TESS_LEVEL;
        gl_TessLevelInner[0] =
        gl_TessLevelInner[1] =
        gl_TessLevelOuter[0] =
        gl_TessLevelOuter[1] =
        gl_TessLevelOuter[2] =
        gl_TessLevelOuter[3] = tessLevel;

        // set output data
        o_Patch[gl_InvocationID].vertices = v;
        o_Patch[gl_InvocationID].u = u;
    }
}
#endif

// -----------------------------------------------------------------------------
/**
 * Tessellation Evaluation Shader
 *
 * This tessellaction evaluation shader is responsible for placing the
 * geometry properly on the input mesh (here a terrain).
 */
#ifdef TESS_EVALUATION_SHADER
layout (isolines, equal_spacing) in;
in Patch {
    vec4 vertices[4];
    float u[2];
} i_Patch[];

layout(location = 0) out float o_TexCoord;

void main()
{
    float u[2] = i_Patch[0].u;
    vec4 v[4] = i_Patch[0].vertices;
    vec4 finalVertex = mix(v[1], v[2], gl_TessCoord.x);

    o_TexCoord = mix(u[0], u[1], gl_TessCoord.x);;
    gl_Position = finalVertex;
}
#endif

// -----------------------------------------------------------------------------
/**
 * Fragment Shader
 *
 * This fragment shader is responsible for shading the final geometry.
 */
#ifdef FRAGMENT_SHADER
layout(location = 0) in float i_TexCoord;
layout(location = 0) out vec4 o_FragColor;

void main()
{
    vec3 myColor = vec3(0.10,0.50,0.10);
    o_FragColor = vec4(myColor, 1);
    o_FragColor = vec4(i_TexCoord, 0, 0, 1);
}

#endif
