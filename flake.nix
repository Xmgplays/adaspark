{
  description = "Compilers and tools for SPARK2014 Ada development";
  inputs = {
    # nixos unstable branch
    nixpkgs.url = "nixpkgs";

      # xmlada library needed for gprbuild. Built with bootstrap.

      xmladasrc = {
        flake = false;
        type = "github";
        owner = "AdaCore";
        repo = "xmlada";
        ref = "21-sustained"; # version 21
      };

      # gprbuild tool

      gprbuildsrc = {
        flake = false;
        type = "github";
        owner = "AdaCore";
        repo = "gprbuild";
        ref = "21-sustained"; # version 21
      };

      gprconfig_kbsrc = {
        flake = false;
        type = "github";
        owner = "AdaCore";
        repo = "gprconfig_kb";
        ref = "21-sustained"; # version 21
      };

      # gnatcoll-core

      gnatcoll-coresrc = {
        flake = false;
        type = "github";
        owner = "AdaCore";
        repo = "gnatcoll-core";
        ref = "21-sustained"; # version 21
      };


      # ASIS tools like gnattest, gnatcheck, etc.
      aunitsrc = {
        flake = false;
        type = "github";
        owner = "AdaCore";
        repo = "aunit";
        ref = "21-sustained"; # tag 20.2
      };

      gnat_utilsrc = {
        flake = false;
        type = "github";
        owner = "simonjwright";
        repo = "gnat_util";
      };
    
        asissrc = {
        flake = false;
          type = "github";
          owner = "simonjwright";
          repo = "asis";
          ref = "fsf";
        };
  };

  outputs = { self, nixpkgs, xmladasrc, gprbuildsrc, gprconfig_kbsrc, aunitsrc, gnat_utilsrc, asissrc, gnatcoll-coresrc }:
    with import nixpkgs { system = "x86_64-linux"; };

    let
      # Spark2014 tools
      sparksrc = fetchFromGitHub {
        owner = "adacore";
        repo = "spark2014";
        rev = "baf358da9a3a6557e39283a216e839e74eaeff3a";
        sha256 = "CJRO1Bd9S7ADqDlTzeG2HmAxse+StsM4aUWDsrwjsTQ=";
        fetchSubmodules = true;
      };

      aliresrc = fetchFromGitHub 
      {
        owner = "alire-project";
        repo = "alire";
        rev = "e5b7d6f07fe8e776f43370fbb1fdf484e95c96de";
        sha256 = "ITun0eJ/4EJK5tXPhdNZic50JMODiOeQxhoT6YfrTHo=";
        fetchSubmodules = true;
      };

      python = python39;
      pythonPackages = python39Packages;

      # Customized environment supporting gprbuild search paths.

      base_env = gcc10Stdenv;

      mk_gpr_path = inputs:
        lib.strings.makeSearchPath "share/gpr" inputs + ":"
        + lib.strings.makeSearchPath "lib/gnat" inputs;

      adaenv_func = include_gprbuild:
        let
          maybe_gpr = if include_gprbuild then [ gprbuild ] else [ ];
          core = (overrideCC base_env gnat10).override {
            name = "adaenv" + (if include_gprbuild then "-boot" else "");
            initialPath = base_env.initialPath ++ maybe_gpr;
          };
        in core // { # use modified mkDerivation function
          mkDerivation = params:
            assert lib.asserts.assertMsg (params ? name)
              "Attribute 'name' of derivation must be specified!";
            let
              new_params = params // {

                # Fix crti.o linker error
                LIBRARY_PATH = params.LIBRARY_PATH or "${adaenv.glibc}/lib";

                # Find installed gpr projects in nix store. Consult
                # GPR manual for search path order
                GPR_PROJECT_PATH =
                  mk_gpr_path ((new_params.buildInputs or [ ]) ++ maybe_gpr);

              };
            in core.mkDerivation new_params;
        };

      adaenv_boot = adaenv_func false; # does not include gprbuild by default
      adaenv = adaenv_func true; # does include gprbuild by default

      xmlada = adaenv_boot.mkDerivation {
        name = "xmlada";
        version = "21";
        buildInputs = [ gprbuild-bootstrap ];
        src = xmladasrc;
        configurePhase = ''
          ./configure --prefix=$prefix --enable-build=Production
        '';
        buildPhase = ''
          make all
        '';
        installPhase = ''
          make install
        '';
      };

      gprbuild-bootstrap = adaenv_boot.mkDerivation {
        name = "gprbuild-bootstrap";
        version = "21";
        src = gprbuildsrc;
        patchPhase = "\n          patchShebangs ./bootstrap.sh\n          ";
        dontConfigure = true;
        dontBuild = true;
        installPhase = ''
          ./bootstrap.sh \
          --with-xmlada="${xmladasrc}" \
          --with-kb="${gprconfig_kbsrc}" \
          --prefix=$prefix 
        '';
      };

      gprbuild = adaenv_boot.mkDerivation {
        name = "gprbuild";
        version = "21";
        buildInputs = [ gprbuild-bootstrap xmlada which ];
        src = gprbuildsrc;
        configurePhase = ''
          make prefix=$prefix BUILD=production setup
        '';
        buildPhase = ''
          make all libgpr.build
        '';
        installPhase = ''
          make install libgpr.install
          mkdir -p $out/share/gprconfig
          cp ${gprconfig_kbsrc}/db/* $out/share/gprconfig/
        '';
      };

      gnatcoll-core = adaenv.mkDerivation {
        name = "gnatcoll-core";
        version = "21";
        buildInputs = [ xmlada ];
        src = gnatcoll-coresrc;
        configurePhase = ''
          make prefix=$prefix BUILD=PROD setup
        '';
      };

      gnatsrc = adaenv.cc.cc.src;

      spark2014 = adaenv.mkDerivation {
        name = "SPARK2014";
        version = "21";
        buildInputs = [
          ocaml
          ocamlPackages.ocamlgraph
          ocamlPackages.menhir
          ocamlPackages.menhirLib
          ocamlPackages.zarith
          ocamlPackages.camlzip
          ocamlPackages.ocplib-simplex
          ocamlPackages.findlib
          ocamlPackages.num
          gnatcoll-core
          python
          pythonPackages.sphinx
          xmlada
        ];
        srcs = [
          sparksrc
          gnatsrc # need to list here to get local uncompressed copy
        ];
        sourceRoot = "source";
        configurePhase = ''
          ln -s ../../gcc-10.3.0/gcc/ada gnat2why/gnat_src \
          && make setup
        '';
        installPhase = ''
          make install-all
          cp -a ./install/. $out
        '';
      };

      aunit = adaenv.mkDerivation {
        name = "AUnit";
        version = "20.2";
        src = aunitsrc;
        installPhase = ''
          make INSTALL=$prefix install
        '';
      };

      gnat_util = adaenv.mkDerivation {
        name = "gnat_util";
        version = "10.1.0";
        srcs = [
          gnat_utilsrc
          gnatsrc # list here to get local uncompressed copy
        ];
        sourceRoot = "source";
        GCC_SRC_BASE = "gcc-10.2.0";
        installPhase = ''
          make prefix=$prefix install
        '';
      };

      asis = adaenv.mkDerivation {
        name = "ASIS";
        version = "gcc-10.1.0";
        src = asissrc;
        buildInputs = [ xmlada aunit gnat_util gnatcoll-core which ];
        postUnpack = ''
          make -C source xsetup-snames
          cp -nr source/gnat/* source/asis/
        '';
        buildPhase = ''
          make all tools
        '';
        installPhase = ''
          make prefix=$prefix install install-tools
        '';
      };

      alire = adaenv.mkDerivation rec {
        name = "alire";
        # v1.0.0 failed to fetch submodules, so using current HEAD
        version = "1.1.0-dev+0f603c29";
        src = aliresrc;

        buildInputs = [ gprbuild git ];

        buildPhase = ''
          gprbuild -j0 -P alr_env
        '';

        installPhase = ''
          install -D bin/alr $out/bin/alr
        '';

      };

      # HERE BEGINS THE THINGS THAT THIS FLAKE PROVIDES:
    in {
      # Derivations (create an environment with `nix shell`)
      inherit xmlada gnatcoll-core asis gnat_util aunit;
      gpr = gprbuild;
      gnat = adaenv.cc;
      spark = spark2014;
      alr = alire;

      # Notes on nix shell and nix develop:
      # "nix develop" will open a shell environment that simulates the build environment
      # for the specified derivation, with default being devShell if it is defined, and
      # defaultPackage if it is not.  If the the derivation has a shellHook, it will be 
      # run.  However, buildEnv is not allowed to have a shellHook for some reason.  The 
      # derivation can be a buildable package (including buildEnv) or not like mkShell.
      #
      # "nix shell" will open a shell environment with the specified *packages* installed
      # on the PATH. The default is defaultPackage.  devShell is not used. shellHooks will 
      # not be run. A mkShell invocation cannot be installed, so it cannot be used with
      # nix shell.

      adaspark = buildEnv {
        name = "adaspark";
        paths = [
          self.gnat
          gnat10.cc # need the original compiler on the path for gprconfig to work
          self.gpr
          self.spark
          self.asis
          self.alr
        ];
      };

      packages.x86_64-linux = {
        inherit (self)
          xmlada gnatcoll-core gnat gpr spark adaspark gnat_util aunit asis;
      };
      defaultPackage.x86_64-linux = self.packages.x86_64-linux.adaspark;
      devShell.x86_64-linux = mkShell {
        buildInputs = [ self.adaspark ];
        LIBRARY_PATH =
          self.gpr.LIBRARY_PATH; # pull out any LIBRARY_PATH from a adaenv derivation
      };

      # End derivations

      # Put the adaenv function in the flake so other users can download it and use its
      # mkDerivation function and other features.
      inherit adaenv fetchFromGitHub fetchgit fetchtarball;
    };
}

