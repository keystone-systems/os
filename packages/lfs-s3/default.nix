{
  lib,
  buildGoModule,
  lfs-s3-src,
}:
buildGoModule {
  pname = "lfs-s3";
  version = "0.2.1";
  src = lfs-s3-src;
  vendorHash = "sha256-CRHfPj5gQ54WA+2LjkLIHta7br03TZ4svfkbcezfUOE=";
  meta = with lib; {
    description = "Git LFS transfer agent for S3 storage";
    homepage = "https://github.com/nicolas-graves/lfs-s3";
    license = licenses.gpl3Plus;
    mainProgram = "lfs-s3";
  };
}
