{
  lib,
  stdenv,
  nodejs_22,
  pnpm_11,
  pnpmConfigHook,
  pnpmBuildHook,
  fetchPnpmDeps,
  makeWrapper,
  src,
}:
let
  version = (builtins.fromJSON (builtins.readFile (src + "/package.json"))).version;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "excaliself";
  inherit version src;

  nativeBuildInputs = [
    nodejs_22
    pnpm_11
    pnpmConfigHook
    pnpmBuildHook
    makeWrapper
  ];

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    pnpm = pnpm_11;
    fetcherVersion = 5;
    hash = "sha256-6oRwKn4wGIpJ2FFfpqtLFyDkG8IwljPjzC8T+TJenVg=";
  };

  installPhase = ''
    runHook preInstall

    # Nitro traces externals into .output/server/node_modules. If it
    # ever materializes a partial @electric-sql/pglite there, it
    # would shadow the complete runtime copy installed below.
    test ! -e .output/server/node_modules/@electric-sql/pglite

    mkdir -p $out/lib/excaliself/node_modules/@electric-sql
    cp -r .output drizzle $out/lib/excaliself/
    # Preview mode imports @electric-sql/pglite from node_modules at
    # runtime, and PGlite reads its wasm from beside its own module,
    # so the package cannot come from the Nitro bundle.
    cp -rL node_modules/@electric-sql/pglite \
      $out/lib/excaliself/node_modules/@electric-sql/pglite

    runHook postInstall
  '';

  postFixup = ''
    makeWrapper ${lib.getExe nodejs_22} $out/bin/excaliself \
      --chdir $out/lib/excaliself \
      --add-flags .output/server/index.mjs \
      --set NODE_ENV production
  '';

  meta = {
    description = "Self-hosted Excalidraw whiteboard";
    homepage = "https://github.com/maciekzygmunt/excaliself";
    changelog = "https://github.com/maciekzygmunt/excaliself/releases/tag/v${version}";
    license = lib.licenses.mit;
    mainProgram = "excaliself";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
})
