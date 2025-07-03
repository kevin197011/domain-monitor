#!/bin/bash

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 默认配置
NAMESPACE="domain-monitor"
RELEASE_NAME="domain-monitor"
CHART_PATH="./helm"
DOMAIN=""
IMAGE_TAG="latest"
DRY_RUN=false
SKIP_ISTIO=false
MONITORING=true

# 帮助信息
show_help() {
    cat << EOF
Domain Monitor Helm & Istio 部署脚本

用法: $0 [选项]

选项:
  -n, --namespace NAMESPACE    Kubernetes 命名空间 (默认: domain-monitor)
  -r, --release RELEASE        Helm release 名称 (默认: domain-monitor)
  -d, --domain DOMAIN          应用域名 (必需)
  -t, --tag TAG               Docker 镜像标签 (默认: latest)
  --dry-run                   只显示将要执行的命令，不实际执行
  --skip-istio                跳过 Istio 配置部署
  --no-monitoring             禁用 Prometheus 监控
  -h, --help                  显示此帮助信息

示例:
  $0 --domain domain-monitor.example.com --tag v1.0.0
  $0 -d domain-monitor.local --skip-istio --dry-run
EOF
}

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 命令执行函数
execute() {
    local cmd="$1"
    local description="$2"

    log_info "$description"

    if [ "$DRY_RUN" = true ]; then
        echo "DRY-RUN: $cmd"
    else
        if eval "$cmd"; then
            log_success "$description 完成"
        else
            log_error "$description 失败"
            exit 1
        fi
    fi
}

# 检查前置条件
check_prerequisites() {
    log_info "检查前置条件..."

    # 检查必需的命令
    local required_commands=("kubectl" "helm")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "$cmd 命令未找到，请先安装"
            exit 1
        fi
    done

    # 检查 Kubernetes 连接
    if ! kubectl cluster-info &> /dev/null; then
        log_error "无法连接到 Kubernetes 集群"
        exit 1
    fi

    # 检查 Istio (如果不跳过)
    if [ "$SKIP_ISTIO" = false ]; then
        if ! kubectl get namespace istio-system &> /dev/null; then
            log_warning "Istio 系统命名空间未找到，请确保 Istio 已安装"
        fi
    fi

    # 检查 Chart 路径
    if [ ! -d "$CHART_PATH" ]; then
        log_error "Helm Chart 路径不存在: $CHART_PATH"
        exit 1
    fi

    log_success "前置条件检查通过"
}

# 创建命名空间
create_namespace() {
    log_info "创建命名空间: $NAMESPACE"

    # 创建命名空间
    execute "kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -" \
            "创建命名空间"

    # 启用 Istio 注入
    if [ "$SKIP_ISTIO" = false ]; then
        execute "kubectl label namespace $NAMESPACE istio-injection=enabled --overwrite" \
                "启用 Istio Sidecar 注入"
    fi
}

# 部署 Helm Chart
deploy_helm_chart() {
    log_info "部署 Helm Chart..."

    local helm_args=(
        "upgrade" "--install" "$RELEASE_NAME" "$CHART_PATH"
        "--namespace" "$NAMESPACE"
        "--set" "image.tag=$IMAGE_TAG"
        "--wait" "--timeout=300s"
    )

    # 添加域名配置
    if [ -n "$DOMAIN" ]; then
        helm_args+=(
            "--set" "istio.virtualService.hosts[0]=$DOMAIN"
            "--set" "istio.gateway.servers[0].hosts[0]=$DOMAIN"
            "--set" "istio.gateway.servers[1].hosts[0]=$DOMAIN"
            "--set" "ingress.hosts[0].host=$DOMAIN"
            "--set" "ingress.tls[0].hosts[0]=$DOMAIN"
        )
    fi

    # 禁用监控
    if [ "$MONITORING" = false ]; then
        helm_args+=("--set" "serviceMonitor.enabled=false")
    fi

    # 跳过 Istio
    if [ "$SKIP_ISTIO" = true ]; then
        helm_args+=("--set" "istio.enabled=false")
    fi

    execute "helm ${helm_args[*]}" "部署 Helm Chart"
}

# 部署 Istio 配置
deploy_istio_config() {
    if [ "$SKIP_ISTIO" = true ]; then
        log_info "跳过 Istio 配置部署"
        return
    fi

    log_info "部署 Istio 配置..."

    if [ -d "./istio" ]; then
        execute "kubectl apply -f ./istio/ -n $NAMESPACE" \
                "部署 Istio 配置"
    else
        log_warning "Istio 配置目录不存在，跳过"
    fi
}

# 验证部署
verify_deployment() {
    log_info "验证部署状态..."

    # 等待 Pod 就绪
    execute "kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=$RELEASE_NAME -n $NAMESPACE --timeout=300s" \
            "等待 Pod 就绪"

    # 检查服务状态
    execute "kubectl get pods,svc,hpa -n $NAMESPACE" \
            "检查资源状态"

    if [ "$SKIP_ISTIO" = false ]; then
        # 检查 Istio 配置
        execute "kubectl get gateway,virtualservice,destinationrule -n $NAMESPACE" \
                "检查 Istio 配置"
    fi
}

# 显示访问信息
show_access_info() {
    log_info "部署完成！访问信息："

    echo -e "\n${GREEN}应用访问:${NC}"

    if [ -n "$DOMAIN" ]; then
        echo "  外部访问: https://$DOMAIN"
        echo "  健康检查: https://$DOMAIN/health"
        echo "  监控指标: https://$DOMAIN/metrics"
    fi

    echo -e "\n${GREEN}内部访问:${NC}"
    echo "  服务名称: $RELEASE_NAME.$NAMESPACE.svc.cluster.local:9394"

    echo -e "\n${GREEN}Kubernetes 命令:${NC}"
    echo "  查看 Pod: kubectl get pods -n $NAMESPACE"
    echo "  查看日志: kubectl logs -l app.kubernetes.io/name=$RELEASE_NAME -n $NAMESPACE"
    echo "  端口转发: kubectl port-forward svc/$RELEASE_NAME 9394:9394 -n $NAMESPACE"

    if [ "$MONITORING" = true ]; then
        echo -e "\n${GREEN}监控访问:${NC}"
        echo "  Prometheus: kubectl port-forward -n monitoring svc/prometheus 9090:9090"
        echo "  Grafana: kubectl port-forward -n monitoring svc/grafana 3000:3000"
    fi

    if [ "$SKIP_ISTIO" = false ]; then
        echo -e "\n${GREEN}Istio 工具:${NC}"
        echo "  代理状态: istioctl proxy-status"
        echo "  配置检查: istioctl analyze -n $NAMESPACE"
        echo "  Kiali: kubectl port-forward -n istio-system svc/kiali 20001:20001"
        echo "  Jaeger: kubectl port-forward -n istio-system svc/jaeger 16686:16686"
    fi

    echo -e "\n${GREEN}Helm 管理:${NC}"
    echo "  查看状态: helm status $RELEASE_NAME -n $NAMESPACE"
    echo "  升级应用: helm upgrade $RELEASE_NAME $CHART_PATH -n $NAMESPACE --set image.tag=NEW_TAG"
    echo "  回滚应用: helm rollback $RELEASE_NAME -n $NAMESPACE"
    echo "  卸载应用: helm uninstall $RELEASE_NAME -n $NAMESPACE"
}

# 参数解析
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -r|--release)
            RELEASE_NAME="$2"
            shift 2
            ;;
        -d|--domain)
            DOMAIN="$2"
            shift 2
            ;;
        -t|--tag)
            IMAGE_TAG="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-istio)
            SKIP_ISTIO=true
            shift
            ;;
        --no-monitoring)
            MONITORING=false
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "未知参数: $1"
            show_help
            exit 1
            ;;
    esac
done

# 验证必需参数
if [ -z "$DOMAIN" ] && [ "$SKIP_ISTIO" = false ]; then
    log_error "当启用 Istio 时，域名参数是必需的"
    echo "使用 --domain 指定域名，或使用 --skip-istio 跳过 Istio 配置"
    exit 1
fi

# 主执行流程
main() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE} Domain Monitor 部署脚本${NC}"
    echo -e "${BLUE}================================${NC}"
    echo

    echo "配置信息:"
    echo "  命名空间: $NAMESPACE"
    echo "  Release: $RELEASE_NAME"
    echo "  域名: ${DOMAIN:-未设置}"
    echo "  镜像标签: $IMAGE_TAG"
    echo "  Dry Run: $DRY_RUN"
    echo "  跳过 Istio: $SKIP_ISTIO"
    echo "  启用监控: $MONITORING"
    echo

    if [ "$DRY_RUN" = false ]; then
        read -p "确认部署？ [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "取消部署"
            exit 0
        fi
    fi

    check_prerequisites
    create_namespace
    deploy_helm_chart
    deploy_istio_config

    if [ "$DRY_RUN" = false ]; then
        verify_deployment
        show_access_info
    fi

    log_success "部署脚本执行完成！"
}

# 执行主函数
main