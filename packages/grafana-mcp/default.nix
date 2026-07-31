{
  lib,
  buildGoModule,
  grafana-mcp-src,
}:
buildGoModule {
  pname = "mcp-grafana";
  version = "unstable";
  src = grafana-mcp-src;
  vendorHash = "sha256-NUarbuK3Eg8LflToR35Oaw3lJLjXCJLYukpJ7G4q5FI=";
  meta = with lib; {
    description = "Grafana MCP server for querying metrics and logs";
    homepage = "https://github.com/grafana/mcp-grafana";
    license = licenses.asl20;
    mainProgram = "mcp-grafana";
  };
}
