# 在 Kubernetes 快速安裝 Jenkins

## 安裝 Helm

```
curl https://raw.githubusercontent.com/helm/helm/master/scripts/get | bash
helm init
```

## 設定 Kubernetes cluster-admin credential

```
kubectl create sa jenkins-deployer
kubectl create clusterrolebinding jenkins-deployer-role --clusterrole=cluster-admin --serviceaccount=default:jenkins-deployer
K8S_ADMIN_CREDENTIAL=$(kubectl describe secret jenkins-deployer | grep token: | awk -F" " '{print $2}')
```

## 下載Lab專用 Jenkins 安裝設定資料

```
git clone https://github.com/eric-systex/devops-hands-on.git
cd devops-hands-on/
helm install jenkins --set Master.K8sAdminCredential=$K8S_ADMIN_CREDENTIAL
```

## 靜候啟動

靜候服務啟動，直到 看到 ` Jenkins  1/1  Running ` 為止

```
watch kubectl get po 
```
## 取得入口 ip

找到入口ip 並登入，帳密為 `admin/password`

```
kubectl get svc
```
