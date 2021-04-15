#!/usr/bin/env bash
# Bash 3 compatible for Darwin

# Version of Pulumi from
# https://www.pulumi.com/docs/get-started/install/versions/
VERSION="2.25.0"

# Grab latest release ${VERSION} from
# https://github.com/pulumi/pulumi-${NAME}/releases
plugins=(
    "auth0=1.11.0"
    "aws=3.38.1"
    "azure-native=0.8.0"
    "azure=3.56.0"
    "azuread=3.6.0"
    "cloudflare=2.15.0"
    "consul=2.10.0"
    "eks=0.23.0"
    "datadog=2.18.0"
    "digitalocean=3.8.0"
    "docker=2.10.0"
    "gcp=4.21.0"
    "github=3.6.0"
    "gitlab=3.9.0"
    "hcloud=0.8.0"
    "kubernetes=2.9.1"
    "mailgun=2.6.0"
    "mysql=2.6.0"
    "openstack=2.19.0"
    "packet=3.2.2"
    "postgresql=2.10.0"
    "random=3.1.1"
    "vault=3.6.0"
    "vsphere=2.14.0"
    "tls=3.4.0"
)

function genMainSrc() {
    local url="https://get.pulumi.com/releases/sdk/pulumi-v${VERSION}-$1-x64.tar.gz"
    local sha256
    sha256=$(nix-prefetch-url "$url")
    echo "      {"
    echo "        url = \"${url}\";"
    echo "        sha256 = \"$sha256\";"
    echo "      }"
}

function genSrcs() {
    for plugVers in "${plugins[@]}"; do
        local plug=${plugVers%=*}
        local version=${plugVers#*=}
        # url as defined here
        # https://github.com/pulumi/pulumi/blob/06d4dde8898b2a0de2c3c7ff8e45f97495b89d82/pkg/workspace/plugins.go#L197
        local url="https://api.pulumi.com/releases/plugins/pulumi-resource-${plug}-v${version}-$1-amd64.tar.gz"
        local sha256
        sha256=$(nix-prefetch-url "$url")
        echo "      {"
        echo "        url = \"${url}\";"
        echo "        sha256 = \"$sha256\";"
        echo "      }"
    done
}

{
  cat <<EOF
# DO NOT EDIT! This file is generated automatically by update.sh
{ }:
{
  version = "${VERSION}";
  pulumiPkgs = {
    x86_64-linux = [
EOF
  genMainSrc "linux"
  genSrcs "linux"
  echo "    ];"
  echo "    x86_64-darwin = ["

  genMainSrc "darwin"
  genSrcs "darwin"
  echo "    ];"
  echo "  };"
  echo "}"
} > data.nix
