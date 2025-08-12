# Minikube Setup Guide

This directory contains scripts and configurations for setting up the Infrastructure Kata project using Minikube for local development and testing.

## Prerequisites

- [Minikube](https://minikube.sigs.k8s.io/docs/start/) installed
- [kubectl](https://kubernetes.io/docs/tasks/tools/) installed
- [Helm](https://helm.sh/docs/intro/install/) installed
- [Docker](https://docs.docker.com/get-docker/) installed and running
- At least 16GB RAM and 4 CPU cores available

## Quick Start

### 1. Setup Minikube Clusters

For Linux/macOS:
```bash
chmod +x setup-clusters.sh
./setup-clusters.sh
```

For Windows (PowerShell):
```powershell
.\setup-clusters.ps1
```

This creates two clusters:
- `infra-cluster` - For Jenkins and OpenTofu
- `application-cluster` - For applications and monitoring

### 2. Deploy Infrastructure Components

```bash
chmod +x deploy-components.sh
./deploy-components.sh
```

This deploys:
- Jenkins (on infra-cluster)
- NGINX Ingress Controller (on application-cluster)
- Prometheus and Grafana (on application-cluster)

### 3. Deploy Applications

```bash
chmod +x deploy-apps.sh
./deploy-apps.sh
```

This builds and deploys:
- Backend Flask API (using Minikube registry for multi-node support)
- Frontend React/Next.js application (using Minikube registry for multi-node support)

**Note:** For single-node clusters, you can also use:
```bash
chmod +x deploy-apps-single-node.sh
./deploy-apps-single-node.sh
```

## Access Information

After successful deployment, you can access:

### Infrastructure Cluster
- **Jenkins**: `http://<infra-cluster-ip>:32000`
  - Username: `admin`
  - Password: `admin123`

### Application Cluster
- **Frontend**: `http://app.local` (add to hosts file)
- **Backend API**: `http://api.local/api/hello` (add to hosts file)
- **Grafana**: `http://<app-cluster-ip>:30030`
  - Username: `admin`
  - Password: `admin123`
- **Prometheus**: `http://<app-cluster-ip>:30090`
- **AlertManager**: `http://<app-cluster-ip>:30093`

## Hosts File Configuration

Add these entries to your hosts file:
```
<application-cluster-ip> api.local
<application-cluster-ip> app.local
```

**Linux/macOS**: `/etc/hosts`
**Windows**: `C:\Windows\System32\drivers\etc\hosts`

## Useful Commands

### Cluster Management
```bash
# Switch between clusters
kubectl config use-context infra-cluster
kubectl config use-context application-cluster

# Get cluster IPs
minikube ip -p infra-cluster
minikube ip -p application-cluster

# Stop clusters
minikube stop -p infra-cluster
minikube stop -p application-cluster

# Delete clusters
minikube delete -p infra-cluster
minikube delete -p application-cluster
```

### Application Management
```bash
# View deployed applications
helm list -A

# Get pod status
kubectl get pods -A

# View logs
kubectl logs -f deployment/backend-api-backend -n applications
kubectl logs -f deployment/frontend-app-frontend-app -n applications

# Port forward to services
kubectl port-forward svc/backend-api-backend 5000:80 -n applications
kubectl port-forward svc/frontend-app-frontend-app 3000:80 -n applications
```

### Monitoring
```bash
# Check Prometheus targets
kubectl port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 -n monitoring

# Access Grafana
kubectl port-forward svc/prometheus-grafana 3000:80 -n monitoring
```

## Troubleshooting

### Common Issues

1. **Insufficient Resources**
   - Ensure Docker has at least 8GB RAM allocated
   - Close other resource-intensive applications

2. **Image Pull Errors**
   - Make sure Docker is running
   - Restart Minikube: `minikube delete && minikube start`

3. **Ingress Not Working**
   - Verify ingress addon: `minikube addons list`
   - Enable if needed: `minikube addons enable ingress`

4. **DNS Resolution**
   - Ensure hosts file entries are correct
   - Try using IP addresses directly

### Logs and Debugging
```bash
# Minikube logs
minikube logs -p <cluster-name>

# Kubernetes events
kubectl get events --sort-by=.metadata.creationTimestamp

# Pod logs
kubectl logs <pod-name> -n <namespace>

# Describe resources
kubectl describe pod <pod-name> -n <namespace>
```

## Cleanup

To completely remove all clusters and data:
```bash
minikube delete -p infra-cluster
minikube delete -p application-cluster
```

## Next Steps

1. Configure Jenkins pipelines for CI/CD
2. Set up monitoring dashboards in Grafana
3. Test the complete application flow
4. Explore scaling and load testing
