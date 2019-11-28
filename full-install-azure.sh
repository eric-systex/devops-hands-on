#######################################################
# 無法在Azure shell或是 aws shell上執行, 因為沒有docker daemon可以使用
# 請使用 在GCP 的cloud : https://console.cloud.google.com
# 新增請直接執行      bash <(curl -L https://raw.githubusercontent.com/eric-systex/devops-hands-on/master/full-install-azure.sh) create
# 其他使用者連線AKS  bash <(curl -L https://raw.githubusercontent.com/eric-systex/devops-hands-on/master/full-install-azure.sh) connect 
# 刪除所有資源請執行  bash <(curl -L https://raw.githubusercontent.com/eric-systex/devops-hands-on/master/full-install-azure.sh) delete 
# 2019/7/31 建立完成  每日產生 700元台幣費用
#######################################################
Randomvar=(awk -v min=100000 -v max=999999 'BEGIN{srand(); print int(min+rand()*(max-min+1))}')
Random=$Randomvar
echo "Random=$Randomvar" >> ~/.my-env

#######################################################
## 請修改下面參數
REGION=eastasia
myResourceGroup=LabResourceGroup$Random
PASSWORD_WIN="P@ssw0rd1234"
myAKSClustername=LabAKSCluster$Random
Registryname=$myResourceGroup$Random
k8sversion=1.14.1
######################################################
# 執行
main() {
if [ $1 = delete ]; then
 azlogin
 deleteResoureGroup
fi
if [ $1 = connect ]; then
 installazcli
 azlogin
 connectaks
fi
if [ $1 = create ]; then
 installazcli
 azlogin
 ResourceGroupCreate
 AKSCreate
 kubeconfig
 setwnodeNoSchedule
 changestorageclass
 installistio
 InstallAcrJenkins
 installEFK
 installKSM
 outputingress
 printVirtualService
 windowspodInwnode
 EnvAndMessage
fi
}
#######################################################

installazcli(){
# 安裝az cli 工具
sudo apt-get install curl apt-transport-https lsb-release gnupg > /dev/null 2>&1
curl -sL https://packages.microsoft.com/keys/microsoft.asc | \
    gpg --dearmor | \
    sudo tee /etc/apt/trusted.gpg.d/microsoft.asc.gpg > /dev/null
AZ_REPO=$(lsb_release -cs)
echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" | \
    sudo tee /etc/apt/sources.list.d/azure-cli.list > /dev/null 2>&1
sudo apt-get update > /dev/null 2>&1
sudo apt-get install azure-cli > /dev/null 2>&1
}

azlogin(){
echo "請依提示上的網址連線並輸入提示的驗證碼和登入azure"
az login

# 載入模組
az extension add --name aks-preview > /dev/null 2>&1
az feature register --name WindowsPreview --namespace Microsoft.ContainerService > /dev/null 2>&1
az provider register --namespace Microsoft.ContainerService > /dev/null 2>&1
}

ResourceGroupCreate(){
# 建立 ResourceGroup
echo "建立名稱為$myResourceGroup 的ResourceGroup"
az group create --name $myResourceGroup --location $REGION > /dev/null 2>&1
}

# 查詢aks 目前的版本
# az aks get-versions --location $REGION

AKSCreate(){
# 列出所需參數
echo "REGION="$REGION
echo "myResourceGroup="$myResourceGroup
echo "myAKSClustername="$myAKSClustername
echo "Registryname="$Registryname
echo "REGION="$REGION >> ~/.my-env
echo "myResourceGroup="$myResourceGroup >> ~/.my-env
echo "myAKSClustername="$myAKSClustername >> ~/.my-env
echo "Registryname="$Registryname >> ~/.my-env

#  建立AKS 和一個預設的node
echo "正在建立AKS以及第三個linux worknode...等待約7~10分鐘"
az aks create \
    --resource-group $myResourceGroup \
    --name $myAKSClustername \
    --node-count 3 \
    --enable-addons monitoring \
    --kubernetes-version $k8sversion \
    --generate-ssh-keys \
    --windows-admin-password $PASSWORD_WIN \
    --windows-admin-username azureuser \
    --enable-vmss \
    --network-plugin azure  > /dev/null 2>&1

# 建立 windows node
# v3 系列的node 例如 Standard_D4s_v3 可以開hyper-v container
echo "建立一個windows worknode...等待7~10分鐘"
az aks nodepool add \
    --resource-group $myResourceGroup \
    --cluster-name $myAKSClustername \
    --os-type Windows \
    --name wnode1 \
    --node-count 1 \
    --node-vm-size Standard_D4s_v3 \
    --kubernetes-version $k8sversion  > /dev/null 2>&1
}


kubeconfig(){
# 安裝kubectl
az aks install-cli > /dev/null 2>&1

# 取得kubectl config
az aks get-credentials --resource-group $myResourceGroup --name $myAKSClustername > /dev/null 2>&1
# kubectl get nodes
}

setwnodeNoSchedule(){
# 使用節點 taint 以避免排程到先佔 VM 節點
kubectl taint nodes akswnode1000000 wnode="true":NoSchedule > /dev/null 2>&1
}


installistio(){
# 建立istio 
echo "安裝istio 1.1.2"
ISTIO_VERSION=1.1.2 > /dev/null 2>&1
curl -sL "https://github.com/istio/istio/releases/download/$ISTIO_VERSION/istio-$ISTIO_VERSION-linux.tar.gz" | tar xz > /dev/null 2>&1

cd istio-$ISTIO_VERSION > /dev/null 2>&1
cp ./bin/istioctl /usr/local/bin/istioctl > /dev/null 2>&1
chmod +x /usr/local/bin/istioctl > /dev/null 2>&1
export PATH=$PATH:$HOME/istio-$ISTIO_VERSION/bin/ > /dev/null 2>&1


# tiller
kubectl apply -f install/kubernetes/helm/helm-service-account.yaml > /dev/null 2>&1
helm init --service-account tiller --node-selectors "beta.kubernetes.io/os"="linux"  > /dev/null 2>&1
sleep 10

## 安裝istio 加入其他工具
kubectl create namespace istio-system > /dev/null 2>&1 
sleep 1
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: kiali
  namespace: istio-system
  labels:
    app: kiali
type: Opaque
data:
  username: YWRtaW4=
  passphrase: c3lzdGV4
EOF

  helm template install/kubernetes/helm/istio-init --name istio-init --namespace istio-system | kubectl apply -f - > /dev/null 2>&1
  helm template install/kubernetes/helm/istio \
    --name istio --namespace istio-system \
    --set sidecarInjectorWebhook.enabled=true \
    --set pilot.traceSampling=1.0 \
    --set pilot.resources.requests.cpu=100m \
    --set pilot.resources.requests.memory=256Mi \
    --set grafana.enabled=true \
    --set tracing.enabled=true \
    --set servicegraph.enabled=true \
    --set kiali.enabled=true \
    --set kiali.createDemoSecret=true \
	--set gateways.istio-egressgateway.enabled=false \
	--set gateways.istio-ingressgateway.sds.enabled=true \
  |  kubectl apply -f - > /dev/null 2>&1
  printf "等待服務啟動中..."
  while [ `kubectl get po -n istio-system | grep istio-sidecar-injector | grep Running | grep '1/1' | wc -l` -eq 0 ]
  do
    sleep 1
  done  
  echo "完成"

  printf "  設定自動注入 sidecar ..."
  kubectl label namespace default istio-injection=enabled > /dev/null 2>&1 && echo "完成"

  printf "  安裝 Bookinfo 範例程式 ..."
  kubectl apply -f samples/bookinfo/platform/kube/bookinfo.yaml > /dev/null 2>&1
  kubectl apply -f samples/bookinfo/networking/bookinfo-gateway.yaml > /dev/null 2>&1
  kubectl apply -f samples/bookinfo/networking/destination-rule-all.yaml > /dev/null 2>&1 && echo "完成"
}

InstallAcrJenkins(){
# ACS & jenkins
az acr create --resource-group $myResourceGroup --name $Registryname --sku Basic > /dev/null 2>&1 && echo "建立ACR"
sleep 6
## loginserver 為 $Registryname.azurecr.io
# az acr login --name $Registryname  # 不能再azure shell執行 因為沒有docker
## ACS 授權 
# https://docs.microsoft.com/zh-tw/azure/container-registry/container-registry-auth-service-principalleep
# 新增AAD service account 授權可以使用ACR
SERVICE_PRINCIPAL_NAME=acr-service-principal
ACR_REGISTRY_ID=$(az acr show --name $Registryname --query id --output tsv) 
SP_PASSWD=$(az ad sp create-for-rbac --name http://$SERVICE_PRINCIPAL_NAME --scopes $ACR_REGISTRY_ID --role owner --query password --output tsv)  > /dev/null 2>&1
SP_APP_ID=$(az ad sp show --id http://$SERVICE_PRINCIPAL_NAME --query appId --output tsv)

## AAD 帳號密碼
echo "ACR可以用的帳號"
echo "Service principal ID: $SP_APP_ID"
echo "ACR可以用的密碼"
echo "Service principal password: $SP_PASSWD"

docker login -u $SP_APP_ID -p $SP_PASSWD $Registryname.azurecr.io > /dev/null 2>&1

echo "上傳必要images 到ACR上"
 docker pull marketplace.gcr.io/google/prometheus/alertmanager:2.2 > /dev/null 2>&1
 docker tag  marketplace.gcr.io/google/prometheus/alertmanager:2.2 $Registryname.azurecr.io/alertmanager:2.2 > /dev/null 2>&1
 docker push $Registryname.azurecr.io/alertmanager:2.2 > /dev/null 2>&1
 
 docker pull marketplace.gcr.io/google/prometheus:2.2 > /dev/null 2>&1
 docker tag  marketplace.gcr.io/google/prometheus:2.2 $Registryname.azurecr.io/prometheus:2.2 > /dev/null 2>&1
 docker push $Registryname.azurecr.io/prometheus:2.2 > /dev/null 2>&1
 
 docker pull marketplace.gcr.io/google/prometheus/nodeexporter:2.2 > /dev/null 2>&1
 docker tag  marketplace.gcr.io/google/prometheus/nodeexporter:2.2 $Registryname.azurecr.io/nodeexporter:2.2 > /dev/null 2>&1
 docker push $Registryname.azurecr.io/nodeexporter:2.2 > /dev/null 2>&1
 
 docker pull marketplace.gcr.io/google/prometheus/kubestatemetrics:2.2 > /dev/null 2>&1
 docker tag  marketplace.gcr.io/google/prometheus/kubestatemetrics:2.2 $Registryname.azurecr.io/kubestatemetrics:2.2 > /dev/null 2>&1
 docker push $Registryname.azurecr.io/kubestatemetrics:2.2 > /dev/null 2>&1
 
 docker pull marketplace.gcr.io/google/prometheus/grafana:2.2 > /dev/null 2>&1
 docker tag  marketplace.gcr.io/google/prometheus/grafana:2.2 $Registryname.azurecr.io/grafana:2.2 > /dev/null 2>&1
 docker push $Registryname.azurecr.io/grafana:2.2 > /dev/null 2>&1
 
 docker pull marketplace.gcr.io/google/prometheus/debian9:2.2 > /dev/null 2>&1
 docker tag  marketplace.gcr.io/google/prometheus/debian9:2.2 $Registryname.azurecr.io/debian9:2.2 > /dev/null 2>&1
 docker push $Registryname.azurecr.io/debian9:2.2 > /dev/null 2>&1
 
 # 建立一個 secret 讓AKS 可以取得ACR
 kubectl create namespace logging > /dev/null 2>&1
 kubectl -n logging create secret docker-registry acr-auth --docker-server $Registryname.azurecr.io --docker-username $SP_APP_ID --docker-password $SP_PASSWD
  # 建立一個讓jenkins 可以用的docker 權限
  kubectl create configmap google-container-key --from-file=.docker/config.json  > /dev/null 2>&1

  kubectl create sa jenkins-deployer > /dev/null 2>&1
  kubectl create clusterrolebinding jenkins-deployer-role --clusterrole=cluster-admin --serviceaccount=default:jenkins-deployer > /dev/null 2>&1
  K8S_ADMIN_CREDENTIAL=$(kubectl describe secret jenkins-deployer | grep token: | awk -F" " '{print $2}')
  cat <<EOF | kubectl apply -f -  > /dev/null 2>&1 && echo "完成"
---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: fabric8-rbac
subjects:
  - kind: ServiceAccount
    name: default
    namespace: default
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
EOF

  printf "  正在安裝 jenkins-slave ... "
  git clone https://github.com/eric-systex/devops-hands-on.git > /dev/null 2>&1
  printf "build..." && docker build -t $Registryname.azurecr.io/jnlp-slave:v1 devops-hands-on/jenkins/slave > /dev/null 2>&1
  printf "push..." && docker push $Registryname.azurecr.io/jnlp-slave:v1 > /dev/null 2>&1
  echo "完成"
  
# 列出目前ACR上的 images
echo "目前在ACR上的 images"
az acr repository list --name $Registryname --output table

  printf "  正在安裝 jenkins:lts ..."
  helm install --name jenkins \
    --set Master.ServiceType=ClusterIP \
    --set Master.K8sAdminCredential=$K8S_ADMIN_CREDENTIAL \
    --set Agent.Image=$Registryname.azurecr.io/jnlp-slave \
    --set Agent.ImageTag=v1 \
    --set Master.AdminPassword=systex \
    --set Master.GoogleProjectId=$myResourceGroup \
    devops-hands-on/jenkins > /dev/null 2>&1 && echo "完成"

}

changestorageclass(){
kubectl delete sc faster > /dev/null 2>&1

cat <<EOF | kubectl apply -f - > /dev/null 2>&1
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  labels:
    kubernetes.io/cluster-service: "true"
  name: faster
parameters:
  cachingmode: ReadOnly
  kind: Managed
  storageaccounttype: Premium_LRS
provisioner: kubernetes.io/azure-disk
reclaimPolicy: Delete
volumeBindingMode: Immediate
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  labels:
    kubernetes.io/cluster-service: "true"
  name: standard
parameters:
  cachingmode: ReadOnly
  kind: Managed
  storageaccounttype: Standard_LRS
provisioner: kubernetes.io/azure-disk
reclaimPolicy: Delete
volumeBindingMode: Immediate
EOF
}

installEFK() {
  echo "安裝 Elasticsearch + Fluentd + Kibana ..."
  printf "  安裝中 ..."
  kubectl apply -f devops-hands-on/logging-efk.yaml > /dev/null 2>&1 && echo "完成"

}

installKSM() {
  echo "安裝 Kube-state-metrics ..."
  printf "  安裝中 ..."
  kubectl apply -f devops-hands-on/kube-state-metrics/app-crd.yaml > /dev/null 2>&1 
  kubectl apply -f devops-hands-on/kube-state-metrics/prometheus-metrics_sa_manifest.yaml --namespace logging > /dev/null 2>&1 
  sleep 1
  sed -i 's/prometheus:2.2/prometheus\/prometheus:2.2/g' devops-hands-on/kube-state-metrics/prometheus-metrics_manifest.yaml
  sleep 1
  sed -i 's/marketplace.gcr.io\/google\/prometheus/Registryname.azurecr.io/g' devops-hands-on/kube-state-metrics/prometheus-metrics_manifest.yaml
  sleep 1
  sed -i "s/Registryname/${Registryname}/g" devops-hands-on/kube-state-metrics/prometheus-metrics_manifest.yaml
  sleep 1
  kubectl apply -f devops-hands-on/kube-state-metrics/prometheus-metrics_manifest.yaml --namespace logging  > /dev/null 2>&1 && echo "完成"
  
  # 讓 AKS 可以去ACR 拉images
  kubectl patch serviceaccount prometheus-metrics-alertmanager -n logging -p '{"imagePullSecrets": [{"name": "acr-auth"}]}' > /dev/null 2>&1
  kubectl patch serviceaccount prometheus-metrics-grafana -n logging -p '{"imagePullSecrets": [{"name": "acr-auth"}]}' > /dev/null 2>&1
  kubectl patch serviceaccount prometheus-metrics-kube-state-metrics -n logging -p '{"imagePullSecrets": [{"name": "acr-auth"}]}' > /dev/null 2>&1
  kubectl patch serviceaccount prometheus-metrics-node-exporter  -n logging -p '{"imagePullSecrets": [{"name": "acr-auth"}]}' > /dev/null 2>&1
  kubectl patch serviceaccount prometheus-metrics-prometheus -n logging -p '{"imagePullSecrets": [{"name": "acr-auth"}]}' > /dev/null 2>&1
  kubectl patch serviceaccount default -n logging -p '{"imagePullSecrets": [{"name": "acr-auth"}]}' > /dev/null 2>&1

  # 刪除因為還沒設定Secrets 的失敗 pod
  while [ `kubectl get po -n logging | grep prometheus-metrics-grafana | grep Running | grep '1/1' | wc -l` -eq 0 ]
  do
  sleep 5
  kubectl delete pod -n logging `kubectl get pods -n logging| awk '$3 == "Init:ImagePullBackOff" {print $1}'` > /dev/null 2>&1
  kubectl delete pod -n logging `kubectl get pods -n logging| awk '$3 == "ImagePullBackOff" {print $1}'` > /dev/null 2>&1
  kubectl delete pod -n logging `kubectl get pods -n logging| awk '$3 == "CrashLoopBackOff" {print $1}'` > /dev/null 2>&1
  done
}

outputingress(){
# 將服務打出來
 INGRESS_HOST=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
 helm template --set istio.ingressgateway.ip=$INGRESS_HOST devops-hands-on/svc | kubectl apply -f - > /dev/null 2>&1
}

printVirtualService(){
kubectl get VirtualService
}

windowspodInwnode(){
####################################################
# Taint nodes NoSchedule
# https://kubernetes.io/docs/setup/production-environment/windows/user-guide-windows-containers/
# sidecar no injection
# https://istio.io/docs/setup/kubernetes/additional-setup/sidecar-injection/
# 如果是使用windows node 時
###  不能給istio的sidecar injector 因為sidecar是linux
#########################################################
cat <<EOF | kubectl apply -f - > /dev/null 2>&1
apiVersion: v1
kind: Service
metadata:
  name: win-webserver
  labels:
    app: win-webserver
spec:
  ports:
  # the port that this service should serve on
  - port: 80
    targetPort: 80
  selector:
    app: win-webserver
  type: NodePort
---
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  labels:
    app: win-webserver
  name: win-webserver
spec:
  replicas: 1
  template:
    metadata:
      labels:
        app: win-webserver
      name: win-webserver
      annotations:
        sidecar.istio.io/inject: "false"
    spec:
      containers:
      - name: windowswebserver
        image: mcr.microsoft.com/windows/servercore:ltsc2019
        command:
        - powershell.exe
        - -command
        - "sleep 1000"
      nodeSelector:
        beta.kubernetes.io/os: windows
      tolerations:
      - key: "wnode"
        operator: "Equal"
        value: "true"
        effect: "NoSchedule"
EOF
}


EnvAndMessage(){
> ~/.my-env
echo "INGRESS_HOST=$INGRESS_HOST" >> ~/.my-env
cat <<EOF
-------------------------------------------------------------
環境安裝完成
----------
Istio Bookinfo 示範程式: http://bookinfo.$INGRESS_HOST.nip.io/
K8S Health Monitoring  : http://grafana.$INGRESS_HOST.nip.io/
Kiali Service Graph    : http://kiali.$INGRESS_HOST.nip.io/kiali/console
Jaeger Tracing         : http://jaeger.$INGRESS_HOST.nip.io/
Kibana Logging         : http://kibana.$INGRESS_HOST.nip.io/
Jenkins CI/CD          : http://jenkins.$INGRESS_HOST.nip.io/
-------------------------------------------------------------
EOF
}

deleteResoureGroup(){
#echo "列出所有ResoureGroup"
#az group list |grep name
echo "刪除ResoureGroup"
for i in `az group list -o tsv --query [].name`; do echo $i && az group delete -n $i  --no-wait; done
}

connectaks(){
az aks install-cli > /dev/null 2>&1
resourceGroup=$(az aks list| jq -r '.[].resourceGroup')
name=$(az aks list| jq -r '.[].name')
az aks get-credentials --resource-group $resourceGroup --name $name
kubectl get nodes
}

##################################################################

main $1

###############################################################
