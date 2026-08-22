{ lib }:
let
  nonEmpty = value: value != null && value != "";
  credentialQueryParameters = [
    "access-key"
    "access_key"
    "aws-access-key-id"
    "aws_access_key_id"
    "aws-secret-access-key"
    "aws_secret_access_key"
    "auth"
    "password"
    "signature"
    "secret"
    "secret-key"
    "secret_key"
    "token"
    "x-amz-credential"
    "x-amz-security-token"
    "x-amz-signature"
  ];
  hasCredentialQueryParameter =
    url:
    let
      lowerUrl = lib.toLower url;
    in
    lib.any (
      parameter: lib.hasInfix "?${parameter}=" lowerUrl || lib.hasInfix "&${parameter}=" lowerUrl
    ) credentialQueryParameters;
  authorityFor =
    url:
    let
      match = builtins.match "https://([^/?#]*)(.*)" url;
    in
    if match == null then "" else builtins.head match;
in
rec {
  hasUrl = cache: nonEmpty (cache.url or null);

  hasPublicKey = cache: nonEmpty (cache.publicKey or null);

  complete = cache: nonEmpty (cache.url or null) && nonEmpty (cache.publicKey or null);

  usable =
    cache:
    (cache.enable or false)
    && nonEmpty (cache.url or null)
    && nonEmpty (cache.publicKey or null)
    && credentialFreeHttpsUrl cache.url;

  credentialFreeHttpsUrl =
    url:
    nonEmpty url
    && lib.hasPrefix "https://" url
    && authorityFor url != ""
    && !(lib.hasInfix "@" (authorityFor url))
    && builtins.match ".*[[:space:]].*" url == null
    && !(hasCredentialQueryParameter url);
}
