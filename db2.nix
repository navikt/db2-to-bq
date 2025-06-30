{
  stdenv,
}:
stdenv.mkDerivation (finalAttrs: rec {
  version = "12.1.0";
  pname = "db2-clidriver";
  src = builtins.fetchTarball {
    url = "https://public.dhe.ibm.com/ibmdl/export/pub/software/data/db2/drivers/odbc_cli/v${finalAttrs.version}/linuxx64_odbc_cli.tar.gz";
    # url = "https://public.dhe.ibm.com/ibmdl/export/pub/software/data/db2/drivers/odbc_cli/v12.1.0/macarm64_odbc_cli.tar.gz";
    sha256 = "sha256:0gzxsxacnsf76qvb7kcr5qs7015z9d601fbf4k3x0xsr65z5d5y1";
  };

  buildPhase = ''
    runHook preBuild

    mkdir -p $out
    cp -r ${src}/* $out

    runHook postBuild
  '';
})
