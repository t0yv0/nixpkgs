#!/usr/bin/env bash
# Bash 3 compatible for Darwin

# Version of Pulumi from
# https://www.pulumi.com/docs/get-started/install/versions/
VERSION="2.23.1"

function lastRel() {
    NAME="$1"
    curl --silent https://github.com/pulumi/pulumi-$NAME/releases |
	grep -o 'v\d\+\.\d\+\.\d\+' |
	head -n 1 |
	sed s/v//
}

# Grab latest release ${VERSION} from
# https://github.com/pulumi/pulumi-${NAME}/releases
plugins=(
    "auth0=$(lastRel auth0)"
    "aws=$(lastRel aws)"
    "cloudflare=$(lastRel cloudflare)"
    "consul=$(lastRel consul)"
    "datadog=$(lastRel datadog)"
    "digitalocean=$(lastRel digitalocean)"
    "docker=$(lastRel docker)"
    "gcp=$(lastRel gcp)"
    "github=$(lastRel github)"
    "gitlab=$(lastRel gitlab)"
    "hcloud=$(lastRel hcloud)"
    "kubernetes=$(lastRel kubernetes)"
    "mailgun=2.4.1"
    "mysql=$(lastRel mysql)"
    "openstack=$(lastRel openstack)"
    "packet=$(lastRel packet)"
    "postgresql=$(lastRel postgresql)"
    "random=$(lastRel random)"
    "vault=$(lastRel vault)"
    "vsphere=$(lastRel vsphere)"
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
