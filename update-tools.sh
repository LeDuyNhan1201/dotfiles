#!/usr/bin/env bash

# ==============================================================================
# Linux DevOps Tools Updater
#
# Supported:
#   kubectl
#   k9s
#   minikube
#   helm
#   docker
#   compose
#   lazydocker
#   lazygit
#   codex
#   git
#   gh
#   node
#   npm
#
# Usage:
#
#   Update everything:
#       ./update-dev-tools.sh
#
#   Update one tool:
#       ./update-dev-tools.sh kubectl
#
#   Update multiple tools:
#       ./update-dev-tools.sh kubectl helm k9s
#
#   Dry run:
#       ./update-dev-tools.sh --dry-run
#       ./update-dev-tools.sh --dry-run kubectl helm
#
#   Help:
#       ./update-dev-tools.sh --help
# ==============================================================================

set -Eeuo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly TMP_DIR="$(mktemp -d)"

DRY_RUN=false

SUPPORTED_TOOLS=(
    kubectl
    k9s
    minikube
    helm
    docker
    compose
    lazydocker
    lazygit
    codex
    git
    gh
    node
    npm
)

# ------------------------------------------------------------------------------
# Cleanup
# ------------------------------------------------------------------------------

cleanup() {
    rm -rf "$TMP_DIR"
}

trap cleanup EXIT

# ------------------------------------------------------------------------------
# Logging
# ------------------------------------------------------------------------------

log() {
    printf '\033[1;34m[INFO]\033[0m %s\n' "$*"
}

success() {
    printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"
}

warn() {
    printf '\033[1;33m[WARN]\033[0m %s\n' "$*"
}

error() {
    printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2
}

die() {
    error "$*"
    exit 1
}

# ------------------------------------------------------------------------------
# Arguments
# ------------------------------------------------------------------------------

REQUESTED_TOOLS=()

for arg in "$@"; do
    case "$arg" in
        --dry-run)
            DRY_RUN=true
            ;;

        -h|--help)
            cat <<EOF

Usage:
  $SCRIPT_NAME [OPTIONS] [TOOLS...]

Options:
  --dry-run       Show what would be updated without changing anything
  -h, --help      Show this help

Tools:
  kubectl
  k9s
  minikube
  helm
  docker
  compose
  lazydocker
  lazygit

Examples:
  $SCRIPT_NAME
  $SCRIPT_NAME kubectl
  $SCRIPT_NAME kubectl helm k9s
  $SCRIPT_NAME --dry-run
  $SCRIPT_NAME --dry-run kubectl helm

If no tool is specified, all tools will be updated.

EOF
            exit 0
            ;;

        *)
            REQUESTED_TOOLS+=("$arg")
            ;;
    esac
done

# ------------------------------------------------------------------------------
# Environment
# ------------------------------------------------------------------------------

if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
else
    die "Cannot detect Linux distribution."
fi

if [[ "${ID:-}" != "linuxmint" && "${ID_LIKE:-}" != *"ubuntu"* ]]; then
    warn "This script is designed primarily for Linux Mint / Ubuntu."
fi

if ! command -v dpkg >/dev/null 2>&1; then
    die "dpkg is required."
fi

ARCH="$(dpkg --print-architecture)"

case "$ARCH" in
    amd64)
        BINARY_ARCH="amd64"
        LAZYDOCKER_ARCH="x86_64"
        LAZYGIT_ARCH="x86_64"
        MINIKUBE_ARCH="amd64"
        HELM_ARCH="amd64"
        ;;

    arm64)
        BINARY_ARCH="arm64"
        LAZYDOCKER_ARCH="arm64"
        LAZYGIT_ARCH="arm64"
        MINIKUBE_ARCH="arm64"
        HELM_ARCH="arm64"
        ;;

    *)
        die "Unsupported architecture: $ARCH"
        ;;
esac

log "OS: ${PRETTY_NAME:-unknown}"
log "Architecture: $ARCH"
log "Dry run: $DRY_RUN"

# ------------------------------------------------------------------------------
# Dependencies
# ------------------------------------------------------------------------------

install_dependencies() {
    local packages=()

    command -v curl >/dev/null 2>&1 || packages+=(curl)
    command -v tar >/dev/null 2>&1 || packages+=(tar)
    command -v sha256sum >/dev/null 2>&1 || packages+=(coreutils)
    command -v dpkg >/dev/null 2>&1 || packages+=(dpkg)

    if (( ${#packages[@]} == 0 )); then
        return
    fi

    log "Installing required packages: ${packages[*]}"

    if "$DRY_RUN"; then
        return
    fi

    sudo apt-get update
    sudo apt-get install -y "${packages[@]}"
}

install_dependencies

# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

version_of() {
    local command="$1"

    if ! command_exists "$command"; then
        printf 'not installed'
        return
    fi

    case "$command" in
        kubectl)
            kubectl version --client 2>/dev/null |
                head -n 1 ||
                true
            ;;

        k9s)
            k9s version --short 2>/dev/null |
                head -n 1 ||
                true
            ;;

        minikube)
            minikube version --short 2>/dev/null |
                head -n 1 ||
                true
            ;;

        helm)
            helm version --short 2>/dev/null |
                head -n 1 ||
                true
            ;;

        docker)
            docker --version 2>/dev/null ||
                true
            ;;

        lazydocker)
            lazydocker --version 2>/dev/null |
                head -n 1 ||
                true
            ;;

        lazygit)
            lazygit --version 2>/dev/null |
                head -n 1 ||
                true
            ;;
        
        codex)
            codex --version 2>/dev/null |
                head -n 1 ||
                true
            ;;
        
        git)
            git --version 2>/dev/null ||
                true
            ;;
        
        gh)
            gh --version 2>/dev/null |
                head -n 1 ||
                true
            ;;
        
        node)
            node --version 2>/dev/null ||
                true
            ;;
        
        npm)
            printf 'v%s\n' "$(npm --version 2>/dev/null)" ||
                true
            ;;
        
        codex)
            codex --version 2>/dev/null |
                head -n 1 ||
                true
            ;;

        *)
            printf 'unknown'
            ;;
    esac
}

get_install_path() {
    local command="$1"

    if command_exists "$command"; then
        command -v "$command"
        return
    fi

    case "$command" in
        kubectl|k9s|minikube|helm|lazydocker|lazygit)
            echo "/usr/local/bin/$command"
            ;;
        *)
            echo ""
            ;;
    esac
}

backup_binary() {
    local path="$1"

    [[ -f "$path" ]] || return 0

    local backup
    backup="${path}.backup.$(date +%Y%m%d-%H%M%S)"

    log "Backing up:"
    log "  $path"
    log "  -> $backup"

    if ! "$DRY_RUN"; then
        sudo cp "$path" "$backup"
    fi
}

download() {
    local url="$1"
    local output="$2"

    log "Downloading:"
    log "  $url"

    if "$DRY_RUN"; then
        return
    fi

    curl \
        --fail \
        --silent \
        --show-error \
        --location \
        --retry 2 \
        --retry-delay 2 \
        --connect-timeout 10 \
        --max-time 60 \
        --speed-time 15 \
        --speed-limit 1024 \
        -o "$output" \
        "$url"
}

install_binary() {
    local name="$1"
    local source="$2"
    local destination="$3"

    [[ -f "$source" ]] ||
        die "Downloaded binary does not exist: $source"

    log "Installing $name:"
    log "  $source"
    log "  -> $destination"

    if "$DRY_RUN"; then
        return
    fi

    backup_binary "$destination"

    sudo install \
        -o root \
        -g root \
        -m 0755 \
        "$source" \
        "$destination"
}

# ------------------------------------------------------------------------------
# GitHub latest release
#
# IMPORTANT:
# Do NOT use api.github.com.
#
# GitHub:
#
#   /releases/latest
#
# redirects to:
#
#   /releases/tag/vX.Y.Z
#
# We use the redirect directly.
# ------------------------------------------------------------------------------

github_latest_tag() {
    local repo="$1"
    local latest_url

    latest_url="$(
        curl \
            --fail \
            --silent \
            --show-error \
            --location \
            --output /dev/null \
            --write-out '%{url_effective}' \
            "https://github.com/${repo}/releases/latest"
    )"

    [[ "$latest_url" == */tag/* ]] ||
        die "Could not determine latest release for $repo"

    printf '%s\n' "${latest_url##*/}"
}

# ------------------------------------------------------------------------------
# git
# ------------------------------------------------------------------------------

update_git() {
    log "========== git =========="

    if ! command_exists git; then
        warn "Git is not installed. Skipping git."
        return
    fi

    local current
    current="$(git --version)"

    log "Current: $current"

    if "$DRY_RUN"; then
        log "Would update git through APT."
        return
    fi

    sudo apt-get update
    sudo apt-get install --only-upgrade -y git

    success "Git updated."
    git --version
}

# ------------------------------------------------------------------------------
# gh
# ------------------------------------------------------------------------------

update_gh() {
    log "========== gh =========="

    if ! command_exists gh; then
        warn "GitHub CLI is not installed. Skipping gh."
        return
    fi

    local current
    current="$(gh --version | head -n 1)"

    log "Current: $current"

    if "$DRY_RUN"; then
        log "Would update gh through APT."
        return
    fi

    sudo apt-get update

    if dpkg-query \
        -W \
        -f='${Status}' \
        gh 2>/dev/null |
        grep -q "install ok installed"; then

        sudo apt-get install --only-upgrade -y gh

        success "gh updated."
        gh --version | head -n 1
    else
        warn "gh is not managed by APT."
        warn "Skipping gh."
    fi
}

# --------------------------------------------------------------------------
# node
# --------------------------------------------------------------------------
    
update_node() {
    log "========== node =========="

    if ! command_exists node; then
        warn "Node.js is not installed. Skipping node."
        return
    fi

    local current
    current="$(node --version)"

    log "Current: $current"

    # --------------------------------------------------------------------------
    # nvm
    # --------------------------------------------------------------------------

    if [[ -s "${NVM_DIR:-$HOME/.nvm}/nvm.sh" ]]; then

        local nvm_dir="${NVM_DIR:-$HOME/.nvm}"

        log "Node.js is managed by nvm."
        log "Using Node.js LTS."

        if "$DRY_RUN"; then
            log "Would run: nvm install --lts"
            log "Would run: nvm alias default 'lts/*'"
            return
        fi

        # shellcheck disable=SC1090
        source "$nvm_dir/nvm.sh"

        nvm install --lts
        nvm alias default 'lts/*'

        success "Node.js updated through nvm."

        node --version
        npm --version

        return
    fi

    # --------------------------------------------------------------------------
    # APT
    # --------------------------------------------------------------------------

    if dpkg-query \
        -W \
        -f='${Status}' \
        nodejs 2>/dev/null |
        grep -q "install ok installed"; then

        log "Node.js is managed by APT."

        if "$DRY_RUN"; then
            log "Would update nodejs through APT."
            return
        fi

        sudo apt-get update
        sudo apt-get install --only-upgrade -y nodejs

        success "Node.js updated through APT."

        node --version
        npm --version

        return
    fi

    warn "Could not determine how Node.js is managed."
    warn "Skipping Node.js."
}

# --------------------------------------------------------------------------
# npm
# --------------------------------------------------------------------------

update_npm() {
    log "========== npm =========="

    if ! command_exists npm; then
        warn "npm is not installed. Skipping npm."
        return
    fi

    local current
    local latest

    current="$(npm --version)"

    latest="$(
        npm view npm version 2>/dev/null
    )"

    [[ -n "$latest" ]] ||
        die "Could not determine latest npm version."

    log "Current: v$current"
    log "Latest:  v$latest"

    if [[ "$current" == "$latest" ]]; then
        success "npm is already up to date."
        return
    fi

    if "$DRY_RUN"; then
        success "Would update npm to v$latest"
        return
    fi

    npm install --global "npm@${latest}"

    success "npm updated to v$(npm --version)"
}

# ------------------------------------------------------------------------------
# kubectl
# ------------------------------------------------------------------------------

update_kubectl() {
    log "========== kubectl =========="

    local latest
    local current
    local binary
    local checksum
    local path

    latest="$(
        curl \
            --fail \
            --silent \
            --show-error \
            --location \
            https://dl.k8s.io/release/stable.txt
    )"

    current="not installed"

    if command_exists kubectl; then
        current="$(
            kubectl version --client -o yaml 2>/dev/null |
                sed -n 's/^[[:space:]]*gitVersion:[[:space:]]*//p' |
                head -n 1
        )"
    fi

    log "Current: $current"
    log "Latest:  $latest"

    if [[ "$current" == "$latest" ]]; then
        success "kubectl is already up to date."
        return
    fi

    binary="$TMP_DIR/kubectl"
    checksum="$TMP_DIR/kubectl.sha256"
    path="$(get_install_path kubectl)"

    download \
        "https://dl.k8s.io/release/${latest}/bin/linux/${BINARY_ARCH}/kubectl" \
        "$binary"

    download \
        "https://dl.k8s.io/release/${latest}/bin/linux/${BINARY_ARCH}/kubectl.sha256" \
        "$checksum"

    if "$DRY_RUN"; then
        success "Would update kubectl to $latest"
        return
    fi

    log "Verifying kubectl checksum..."

    (
        cd "$TMP_DIR"
        echo "$(cat kubectl.sha256)  kubectl" |
            sha256sum --check
    )

    success "kubectl checksum verified."

    install_binary \
        kubectl \
        "$binary" \
        "$path"

    success "kubectl updated to $latest"
}

# ------------------------------------------------------------------------------
# k9s
# ------------------------------------------------------------------------------

update_k9s() {
    log "========== k9s =========="

    local tag
    local archive
    local path

    tag="$(github_latest_tag derailed/k9s)"

    log "Latest: $tag"

    archive="$TMP_DIR/k9s.tar.gz"

    case "$ARCH" in
        amd64)
            download \
                "https://github.com/derailed/k9s/releases/download/${tag}/k9s_Linux_amd64.tar.gz" \
                "$archive"
            ;;

        arm64)
            download \
                "https://github.com/derailed/k9s/releases/download/${tag}/k9s_Linux_arm64.tar.gz" \
                "$archive"
            ;;

        *)
            die "Unsupported architecture for k9s: $ARCH"
            ;;
    esac

    if "$DRY_RUN"; then
        success "Would update k9s to $tag"
        return
    fi

    tar -xzf "$archive" -C "$TMP_DIR"

    [[ -f "$TMP_DIR/k9s" ]] ||
        die "k9s binary was not found in archive."

    path="$(get_install_path k9s)"

    install_binary \
        k9s \
        "$TMP_DIR/k9s" \
        "$path"

    success "k9s updated to $tag"
}

# ------------------------------------------------------------------------------
# minikube
# ------------------------------------------------------------------------------

update_minikube() {
    log "========== minikube =========="

    local current
    local deb
    local path

    current="not installed"

    if command_exists minikube; then
        current="$(
            minikube version --short 2>/dev/null |
                head -n 1
        )"
    fi

    log "Current: $current"

    deb="$TMP_DIR/minikube.deb"

    download \
        "https://storage.googleapis.com/minikube/releases/latest/minikube_latest_${MINIKUBE_ARCH}.deb" \
        "$deb"

    if "$DRY_RUN"; then
        success "Would update minikube"
        return
    fi

    log "Installing minikube package..."

    sudo dpkg -i "$deb"

    # Resolve dependencies if necessary.
    sudo apt-get install -f -y

    success "minikube updated."

    minikube version
}

# ------------------------------------------------------------------------------
# Helm
# ------------------------------------------------------------------------------

update_helm() {
    log "========== helm =========="

    local current
    local latest
    local archive
    local binary
    local path

    current="not installed"

    if command_exists helm; then
        current="$(helm version --short 2>/dev/null || echo "unknown")"
    fi

    latest="$(
        curl \
            --fail \
            --silent \
            --show-error \
            --location \
            https://get.helm.sh/helm-latest-version
    )"

    latest="${latest#v}"

    log "Current: $current"
    log "Latest:  v${latest}"

    archive="$TMP_DIR/helm.tar.gz"

    download \
        "https://get.helm.sh/helm-v${latest}-linux-${HELM_ARCH}.tar.gz" \
        "$archive"

    if "$DRY_RUN"; then
        success "Would update helm to v${latest}"
        return
    fi

    tar -xzf "$archive" -C "$TMP_DIR"

    binary="$TMP_DIR/linux-${HELM_ARCH}/helm"

    [[ -f "$binary" ]] ||
        die "Helm binary was not found in archive."

    path="$(get_install_path helm)"

    install_binary \
        helm \
        "$binary" \
        "$path"

    success "helm updated to v${latest}"
}

# ------------------------------------------------------------------------------
# Docker
# ------------------------------------------------------------------------------

update_docker() {
    log "========== docker =========="

    if ! command_exists docker; then
        warn "Docker is not installed. Skipping docker."
        return
    fi

    log "Current:"
    docker --version

    if "$DRY_RUN"; then
        log "Would update Docker packages through APT."
        return
    fi

    sudo apt-get update

    local packages=(
        docker-ce
        docker-ce-cli
        containerd.io
        docker-buildx-plugin
        docker-compose-plugin
    )

    local installed_packages=()

    for package in "${packages[@]}"; do
        if dpkg-query \
            -W \
            -f='${Status}' \
            "$package" 2>/dev/null |
            grep -q "install ok installed"; then

            installed_packages+=("$package")
        fi
    done

    if (( ${#installed_packages[@]} == 0 )); then
        warn "Docker packages are not managed by the expected Docker APT packages."
        warn "Skipping docker."
        return
    fi

    sudo apt-get install \
        --only-upgrade \
        -y \
        "${installed_packages[@]}"

    success "Docker updated."

    docker --version
}

# ------------------------------------------------------------------------------
# Docker Compose
# ------------------------------------------------------------------------------

update_compose() {
    log "========== docker compose =========="

    if ! command_exists docker; then
        warn "Docker is not installed. Skipping compose."
        return
    fi

    if ! docker compose version >/dev/null 2>&1; then
        warn "Docker Compose plugin is not installed."
        return
    fi

    log "Current:"
    docker compose version

    if "$DRY_RUN"; then
        log "Would update docker-compose-plugin through APT."
        return
    fi

    sudo apt-get update

    if dpkg-query \
        -W \
        -f='${Status}' \
        docker-compose-plugin 2>/dev/null |
        grep -q "install ok installed"; then

        sudo apt-get install \
            --only-upgrade \
            -y \
            docker-compose-plugin

        success "Docker Compose updated."
        docker compose version
    else
        warn "docker-compose-plugin is not managed by APT."
        warn "Skipping compose."
    fi
}

# ------------------------------------------------------------------------------
# lazydocker
# ------------------------------------------------------------------------------

update_lazydocker() {
    log "========== lazydocker =========="

    local tag
    local installer
    local path
    local install_dir

    tag="$(github_latest_tag jesseduffield/lazydocker)"

    log "Latest: $tag"

    installer="$TMP_DIR/lazydocker-install.sh"
    install_dir="/usr/local/bin"

    download \
        "https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh" \
        "$installer"

    if "$DRY_RUN"; then
        success "Would update lazydocker to $tag"
        return
    fi

    chmod +x "$installer"

    log "Running lazydocker official installer..."
    log "Install directory: $install_dir"

    # IMPORTANT:
    # Run installer from TMP_DIR so it cannot conflict with files/directories
    # in the user's current project directory.
    (
        cd "$TMP_DIR"

        sudo env \
            DIR="$install_dir" \
            "$installer"
    )

    path="$install_dir/lazydocker"

    [[ -x "$path" ]] ||
        die "lazydocker was not installed at $path"

    success "lazydocker updated to $tag."

    "$path" --version || true
}

# ------------------------------------------------------------------------------
# lazygit
# ------------------------------------------------------------------------------

update_lazygit() {
    log "========== lazygit =========="

    local tag
    local version
    local archive
    local path

    tag="$(github_latest_tag jesseduffield/lazygit)"
    version="${tag#v}"

    log "Latest: $tag"

    archive="$TMP_DIR/lazygit.tar.gz"

    case "$ARCH" in
        amd64)
            download \
                "https://github.com/jesseduffield/lazygit/releases/download/${tag}/lazygit_${version}_Linux_x86_64.tar.gz" \
                "$archive"
            ;;

        arm64)
            download \
                "https://github.com/jesseduffield/lazygit/releases/download/${tag}/lazygit_${version}_Linux_arm64.tar.gz" \
                "$archive"
            ;;

        *)
            die "Unsupported architecture for lazygit: $ARCH"
            ;;
    esac

    if "$DRY_RUN"; then
        success "Would update lazygit to $tag"
        return
    fi

    tar -xzf "$archive" -C "$TMP_DIR"

    [[ -f "$TMP_DIR/lazygit" ]] ||
        die "lazygit binary was not found in archive."

    path="$(get_install_path lazygit)"

    install_binary \
        lazygit \
        "$TMP_DIR/lazygit" \
        "$path"

    success "lazygit updated to $tag"
}

# ------------------------------------------------------------------------------
# codex
# ------------------------------------------------------------------------------

update_codex() {
    log "========== codex =========="

    if ! command_exists npm; then
        warn "npm is not installed. Skipping codex."
        return
    fi

    local current
    local latest

    current="not installed"

    if command_exists codex; then
        current="$(codex --version 2>/dev/null || echo "unknown")"
    fi

    latest="$(
        npm view @openai/codex version
    )"

    log "Current: $current"
    log "Latest:  v${latest}"

    if [[ "$current" == *"$latest"* ]]; then
        success "codex is already up to date."
        return
    fi

    if "$DRY_RUN"; then
        success "Would update codex to v${latest}"
        return
    fi

    log "Updating @openai/codex..."

    npm install \
        --global \
        "@openai/codex@${latest}"

    success "codex updated to v${latest}."

    codex --version
}

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------

print_summary() {
    echo
    echo "=============================================================="
    echo "                    INSTALLED VERSIONS"
    echo "=============================================================="

    printf "%-15s %s\n" \
        "kubectl:" \
        "$(version_of kubectl)"

    printf "%-15s %s\n" \
        "k9s:" \
        "$(version_of k9s)"

    printf "%-15s %s\n" \
        "minikube:" \
        "$(version_of minikube)"

    printf "%-15s %s\n" \
        "helm:" \
        "$(version_of helm)"

    printf "%-15s %s\n" \
        "docker:" \
        "$(version_of docker)"

    if command_exists docker &&
        docker compose version >/dev/null 2>&1; then

        printf "%-15s %s\n" \
            "compose:" \
            "$(docker compose version)"
    else
        printf "%-15s %s\n" \
            "compose:" \
            "not installed"
    fi

    printf "%-15s %s\n" \
        "lazydocker:" \
        "$(version_of lazydocker)"

    printf "%-15s %s\n" \
        "lazygit:" \
        "$(version_of lazygit)"
    
    printf "%-15s %s\n" \
        "codex:" \
        "$(version_of codex)"

    echo "=============================================================="
}

# ------------------------------------------------------------------------------
# Tool validation
# ------------------------------------------------------------------------------

is_supported_tool() {
    local tool="$1"

    for supported in "${SUPPORTED_TOOLS[@]}"; do
        if [[ "$tool" == "$supported" ]]; then
            return 0
        fi
    done

    return 1
}

validate_requested_tools() {
    local tool

    for tool in "${REQUESTED_TOOLS[@]}"; do
        if ! is_supported_tool "$tool"; then
            error "Unknown tool: $tool"
            echo
            echo "Supported tools:"
            printf '  %s\n' "${SUPPORTED_TOOLS[@]}"
            exit 1
        fi
    done
}

# ------------------------------------------------------------------------------
# Update dispatcher
# ------------------------------------------------------------------------------

update_tool() {
    local tool="$1"

    case "$tool" in
        kubectl)
            update_kubectl
            ;;

        k9s)
            update_k9s
            ;;

        minikube)
            update_minikube
            ;;

        helm)
            update_helm
            ;;

        docker)
            update_docker
            ;;

        compose)
            update_compose
            ;;

        lazydocker)
            update_lazydocker
            ;;

        lazygit)
            update_lazygit
            ;;
        
        codex)
            update_codex
            ;;
        
        git)
            update_git
            ;;
        
        gh)
            update_gh
            ;;
        
        node)
            update_node
            ;;
        
        npm)
            update_npm
            ;;
        
        codex)
            update_codex
            ;;

        *)
            die "Unsupported tool: $tool"
            ;;
    esac
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------

main() {
    validate_requested_tools

    local tools=()

    if (( ${#REQUESTED_TOOLS[@]} == 0 )); then
        tools=("${SUPPORTED_TOOLS[@]}")
        log "No tool specified. Updating all tools."
    else
        tools=("${REQUESTED_TOOLS[@]}")
        log "Updating selected tools: ${tools[*]}"
    fi

    echo

    local tool

    for tool in "${tools[@]}"; do
        update_tool "$tool"
        echo
    done

    if "$DRY_RUN"; then
        warn "Dry-run completed. No changes were made."
    else
        print_summary
        success "Update completed successfully."
    fi
}

main "$@"
