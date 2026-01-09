float4 main(float2 pos : Position) : SV_Position
{
  return float4(pos.x, pos.y, 0.0, 1.0);
}
