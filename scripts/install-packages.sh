#!/usr/bin/env bash
set -euo pipefail

# Installs local tooling required by ICT-Studio-INFRA:
#   - Terraform (init-backend.sh, terraform_files)
#   - AWS CLI v2 (init-backend-ci.sh, aws secretsmanager, etc.)
#   - git, curl, unzip, gnupg, jq (supporting utilities)

OS=""
DISTRO_ID=""
DISTRO_LIKE=""
DISTRO_VERSION_ID=""
PKG_MANAGER=""

log() {
  echo "==> $*"
}

run_privileged() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    echo "ERROR: root privileges required: $*" >&2
    exit 1
  fi
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

detect_platform() {
  case "$(uname -s)" in
    Linux)
      OS="linux"
      if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        DISTRO_ID="${ID:-unknown}"
        DISTRO_LIKE="${ID_LIKE:-}"
        DISTRO_VERSION_ID="${VERSION_ID:-}"
      else
        DISTRO_ID="unknown"
      fi
      ;;
    Darwin)
      OS="macos"
      ;;
    MINGW*|MSYS*|CYGWIN*)
      OS="windows"
      ;;
    *)
      echo "ERROR: unsupported operating system: $(uname -s)" >&2
      exit 1
      ;;
  esac
}

detect_pkg_manager() {
  if [[ "$OS" == "macos" ]]; then
    PKG_MANAGER="brew"
    return
  fi

  if [[ "$OS" != "linux" ]]; then
    return
  fi

  case "$DISTRO_ID" in
    ubuntu|debian|linuxmint|pop)
      PKG_MANAGER="apt"
      ;;
    fedora)
      PKG_MANAGER="dnf"
      ;;
    rhel|centos|rocky|almalinux|ol)
      if command_exists dnf; then
        PKG_MANAGER="dnf"
      else
        PKG_MANAGER="yum"
      fi
      ;;
    amzn)
      if command_exists dnf; then
        PKG_MANAGER="dnf"
      else
        PKG_MANAGER="yum"
      fi
      ;;
    arch|manjaro)
      PKG_MANAGER="pacman"
      ;;
    alpine)
      PKG_MANAGER="apk"
      ;;
    *)
      if [[ "$DISTRO_LIKE" == *debian* ]] && command_exists apt-get; then
        PKG_MANAGER="apt"
      elif [[ "$DISTRO_LIKE" == *rhel* ]] || [[ "$DISTRO_LIKE" == *fedora* ]]; then
        if command_exists dnf; then
          PKG_MANAGER="dnf"
        elif command_exists yum; then
          PKG_MANAGER="yum"
        fi
      fi
      ;;
  esac

  if [[ -z "$PKG_MANAGER" ]]; then
    echo "ERROR: unsupported Linux distribution: ${DISTRO_ID:-unknown}" >&2
    echo "Supported: Debian/Ubuntu, RHEL/CentOS/Rocky/Alma, Fedora, Amazon Linux, Arch, Alpine" >&2
    exit 1
  fi
}

run_pkg_install() {
  if [[ "$PKG_MANAGER" == "dnf" ]]; then
    run_privileged dnf install -y "$@"
  else
    run_privileged yum install -y "$@"
  fi
}

hashicorp_rpm_repo_url() {
  case "$DISTRO_ID" in
    fedora)
      echo "https://rpm.releases.hashicorp.com/fedora/hashicorp.repo"
      ;;
    amzn)
      echo "https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo"
      ;;
    rhel|centos|rocky|almalinux|ol)
      echo "https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo"
      ;;
    *)
      if [[ "$DISTRO_LIKE" == *fedora* ]] && [[ "$DISTRO_LIKE" != *rhel* ]]; then
        echo "https://rpm.releases.hashicorp.com/fedora/hashicorp.repo"
      else
        echo "https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo"
      fi
      ;;
  esac
}

normalize_hashicorp_repo() {
  local repo_file="/etc/yum.repos.d/hashicorp.repo"
  local releasever=""

  case "$DISTRO_ID" in
    amzn)
      releasever="$DISTRO_VERSION_ID"
      ;;
    rhel|centos|rocky|almalinux|ol)
      if [[ -n "$DISTRO_VERSION_ID" ]]; then
        releasever="${DISTRO_VERSION_ID%%.*}"
      elif command_exists rpm; then
        releasever="$(rpm -E '%{rhel}' 2>/dev/null || true)"
        if [[ "$releasever" == "(none)" ]]; then
          releasever=""
        fi
      fi
      ;;
  esac

  if [[ -n "$releasever" ]]; then
    log "Normalizing HashiCorp repo releasever -> ${releasever}"
    run_privileged sed -i "s/\\\$releasever/${releasever}/g" "$repo_file"
  fi
}

install_aws_cli_v2_official() {
  log "Installing AWS CLI v2 (official installer)"
  local tmp_dir arch installer
  tmp_dir="$(mktemp -d)"
  arch="$(uname -m)"
  case "$arch" in
    x86_64) installer="awscli-exe-linux-x86_64.zip" ;;
    aarch64|arm64) installer="awscli-exe-linux-aarch64.zip" ;;
    *)
      echo "ERROR: unsupported architecture for AWS CLI: $arch" >&2
      rm -rf "$tmp_dir"
      exit 1
      ;;
  esac
  curl -fsSL "https://awscli.amazonaws.com/${installer}" -o "${tmp_dir}/awscliv2.zip"
  unzip -q "${tmp_dir}/awscliv2.zip" -d "${tmp_dir}"
  run_privileged "${tmp_dir}/aws/install" --update
  rm -rf "$tmp_dir"
}

install_base_packages() {
  case "$PKG_MANAGER" in
    apt)
      log "Installing base packages (apt)"
      run_privileged apt-get update -qq
      run_privileged apt-get install -y \
        ca-certificates curl gnupg unzip git jq lsb-release
      ;;
    dnf)
      log "Installing base packages (dnf)"
      run_privileged dnf install -y \
        ca-certificates curl gnupg2 unzip git jq tar
      ;;
    yum)
      log "Installing base packages (yum)"
      run_privileged yum install -y \
        ca-certificates curl gnupg2 unzip git jq tar
      ;;
    pacman)
      log "Installing base packages (pacman)"
      run_privileged pacman -Sy --noconfirm \
        ca-certificates curl gnupg unzip git jq tar
      ;;
    apk)
      log "Installing base packages (apk)"
      run_privileged apk add --no-cache \
        ca-certificates curl gnupg unzip git jq tar
      ;;
    brew)
      if ! command_exists brew; then
        echo "ERROR: Homebrew is required on macOS. Install it from https://brew.sh" >&2
        exit 1
      fi
      log "Installing base packages (brew)"
      brew install curl unzip git jq gnupg
      ;;
  esac
}

install_terraform_apt() {
  log "Installing Terraform (HashiCorp apt repository)"
  if ! [[ -f /usr/share/keyrings/hashicorp-archive-keyring.gpg ]]; then
    curl -fsSL https://apt.releases.hashicorp.com/gpg \
      | run_privileged gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  fi

  local codename
  codename="$(. /etc/os-release && echo "${VERSION_CODENAME:-}")"
  if [[ -z "$codename" ]] && command_exists lsb_release; then
    codename="$(lsb_release -cs)"
  fi
  if [[ -z "$codename" ]]; then
    echo "ERROR: could not determine Debian/Ubuntu codename for HashiCorp apt repo" >&2
    exit 1
  fi

  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com ${codename} main" \
    | run_privileged tee /etc/apt/sources.list.d/hashicorp.list >/dev/null

  run_privileged apt-get update -qq
  run_privileged apt-get install -y terraform
}

install_terraform_rpm() {
  local repo_url repo_file="/etc/yum.repos.d/hashicorp.repo"

  repo_url="$(hashicorp_rpm_repo_url)"
  log "Installing Terraform (HashiCorp rpm repository: ${repo_url})"
  curl -fsSL "$repo_url" | run_privileged tee "$repo_file" >/dev/null
  normalize_hashicorp_repo
  run_pkg_install terraform
}

install_terraform() {
  if command_exists terraform; then
    log "Terraform already installed: $(terraform version | head -n1)"
    return
  fi

  case "$PKG_MANAGER" in
    apt)
      install_terraform_apt
      ;;
    dnf|yum)
      install_terraform_rpm
      ;;
    pacman)
      log "Installing Terraform (pacman)"
      run_privileged pacman -S --noconfirm terraform
      ;;
    apk)
      log "Installing Terraform (apk community)"
      run_privileged apk add --no-cache terraform
      ;;
    brew)
      log "Installing Terraform (brew)"
      brew install terraform
      ;;
  esac
}

install_aws_cli() {
  if command_exists aws; then
    log "AWS CLI already installed: $(aws --version 2>&1 | head -n1)"
    return
  fi

  case "$PKG_MANAGER" in
    apt|dnf|yum)
      install_aws_cli_v2_official
      ;;
    pacman)
      log "Installing AWS CLI (pacman)"
      run_privileged pacman -S --noconfirm aws-cli
      ;;
    apk)
      log "Installing AWS CLI (apk)"
      run_privileged apk add --no-cache aws-cli
      ;;
    brew)
      log "Installing AWS CLI (brew)"
      brew install awscli
      ;;
  esac
}

print_windows_instructions() {
  cat <<'EOF'
Windows detected. This shell script targets Linux/macOS.

Install the required tools on Windows with one of the following:

  winget install Hashicorp.Terraform
  winget install Amazon.AWSCLI

Or with Chocolatey:

  choco install terraform awscli

Then run:

  .\scripts\init-backend.ps1

Alternatively, use WSL (Ubuntu) and run:

  bash scripts/install-packages.sh
EOF
}

verify_installation() {
  local missing=0

  for cmd in terraform aws git curl; do
    if command_exists "$cmd"; then
      log "$cmd: OK"
    else
      echo "ERROR: $cmd is not available in PATH" >&2
      missing=1
    fi
  done

  if [[ "$missing" -ne 0 ]]; then
    exit 1
  fi

  echo
  echo "All required packages are ready."
  echo
  echo "Next:"
  echo "  aws configure          # or use an IAM role / AWS SSO profile"
  echo "  bash scripts/init-backend.sh"
  echo "  cd terraform_files && terraform plan"
}

main() {
  detect_platform

  if [[ "$OS" == "windows" ]]; then
    print_windows_instructions
    exit 0
  fi

  detect_pkg_manager

  log "Detected platform: os=$OS distro=${DISTRO_ID:-n/a} pkg_manager=$PKG_MANAGER"

  install_base_packages
  install_terraform
  install_aws_cli
  verify_installation
}

main "$@"
