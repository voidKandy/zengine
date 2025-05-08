#version 330

in vec2 fragTexCoord;
in vec3 fragNormal;

out vec4 finalColor;

void main()
{
    vec3 baseColor = vec3(1.0, 0.4, 0.2); // Orange-ish
    finalColor = vec4(baseColor, 1.0);
}
