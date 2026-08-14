{ lib, buildGoModule, buildNpmPackage, fetchFromGitHub, fetchurl }:

let
  version = "1.33.0";
  src = fetchFromGitHub {
    owner = "lerd-env"; repo = "lerd"; rev = "v${version}";
    hash = "sha256-Gz3TDeJt4MGElRS9dOB/ZPqfBxjQTBudc23ph22O7j4=";
  };

  # The UI's `paraglide-js compile` step (run as part of `npm run build`) loads
  # the inlang message-format plugin listed in project.inlang/settings.json. That
  # entry is a https://cdn.jsdelivr.net URL, which the inlang SDK fetches at build
  # time — impossible in the network-isolated Nix sandbox, leaving the dashboard's
  # i18n messages uncompiled. Vendor the plugin and rewrite the module reference to
  # a data: URI, which the SDK's fetch() resolves offline.
  messageFormatPluginUrl = "https://cdn.jsdelivr.net/npm/@inlang/plugin-message-format@4/dist/index.js";
  messageFormatPlugin = fetchurl {
    url = messageFormatPluginUrl;
    hash = "sha256-lIZViAHAjrsBgiPFHCBEtsPCP8KowOeJSleIKzT+tso=";
  };

  ui = buildNpmPackage {
    pname = "lerd-ui"; inherit version src;
    sourceRoot = "${src.name}/internal/ui/web";
    npmDepsHash = "sha256-SEUCCGWMEmX9KeqJFVc/kME3l33FhENt8ZawqUJZZl0=";
    postPatch = ''
      b64=$(base64 -w0 ${messageFormatPlugin})
      substituteInPlace project.inlang/settings.json \
        --replace-fail "${messageFormatPluginUrl}" "data:text/javascript;base64,$b64"
    '';
    installPhase = "runHook preInstall; cp -r dist $out; runHook postInstall";
  };
in
buildGoModule {
  pname = "lerd"; inherit version src;
  vendorHash = "sha256-2PnSsYgtoEq5nHqRDgafoL1vqV2iGF1J0RLM0pGjEnI=";
  # 1.30+ writes an always-up dummy link (lerd0) and empties systemd-resolved's
  # FallbackDNS; 1.31+ installs DNS sudoers via `lerd bootstrap --system` so
  # later start/watcher repairs apply that without a prompt. On NixOS those
  # files take down all name resolution. Skip host resolver mutation; NixOS
  # already routes only ~test to lerd-dns from configuration.nix.
  patches = [ ./patches/skip-host-resolver-on-nixos.patch ];
  subPackages = [ "cmd/lerd" ];
  tags = [ "nogui" ];
  env.CGO_ENABLED = 0;
  ldflags = [
    "-s" "-w"
    "-X github.com/geodro/lerd/internal/version.Version=${version}"
    "-X github.com/geodro/lerd/internal/version.Commit=v${version}"
    "-X github.com/geodro/lerd/internal/version.Date=1970-01-01T00:00:00Z"
  ];
  preBuild = "cp -r ${ui} internal/ui/web/dist";
  meta = {
    description = "Herd-like local PHP development for Linux and macOS";
    homepage = "https://lerd.sh";
    license = lib.licenses.mit;
    mainProgram = "lerd";
    platforms = lib.platforms.unix;
  };
}
