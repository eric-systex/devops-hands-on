#####################################################################
# 建立一個 service account gcp-sa
# 建立兩組 Cloud Scheduler +Cloud Functions + VM , VM 執行完畢後自動關機
# 晚上7:30 將GKE worknode數量設為0
# 白天8:00 將GKE worknode數量設為3
#####################################################################

project=$(gcloud config list --format 'value(core.project)')
CLUSTERNAME=$(gcloud container clusters list  --format 'value(name)')
zone=$(gcloud container clusters list  --format 'value(zone)')

# 建立GCP service account : gcp-sa  並產生 key.json
gcloud iam service-accounts create gcp-sa --display-name "scale-gke-sa"
servicesa=gcp-sa@$project.iam.gserviceaccount.com
gcloud projects add-iam-policy-binding $project \
  --member serviceAccount:$servicesa \
  --role roles/owner

gcloud iam service-accounts keys create --iam-account $servicesa key.json

#########################################
# 建立scalein VM 所要執行的bash shell
#########################################
SIZE=0

cat <<EOF >> scaleinrun.sh
#! /bin/bash
# Installs apache and a custom homepage
sudo su -
export CLOUD_SDK_REPO="cloud-sdk-$(lsb_release -c -s)"
echo "deb http://packages.cloud.google.com/apt $CLOUD_SDK_REPO main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
sudo apt-get update -y  && sudo apt-get install google-cloud-sdk -y
sudo apt-get install google-cloud-sdk-app-engine-java -y
touch /root/sakey.json
EOF
echo "cat <<EOF >> sakey.json" >> scaleinrun.sh
cat key.json >> scaleinrun.sh
echo "EOF" >> scaleinrun.sh


## 使用 $servicesa  驗證
echo "gcloud auth activate-service-account $servicesa --key-file=/root/sakey.json --project=$project" >> scaleinrun.sh
## 調整叢集大小
echo "gcloud --quiet container clusters resize $CLUSTERNAME --node-pool default-pool --size $SIZE" --zone $zone>> scaleinrun.sh
## 自殺VM 目前用不到
## echo "gcloud compute instances delete  INSTANCE_NAMES scalein-jobvm --delete-disks=all" >> scaleinrun.sh

## 自己關機
echo "init 0" >> scaleinrun.sh

############################################


# 新增scalein-jobvm VM
### https://cloud.google.com/compute/docs/startupscript?hl=zh-tw

gcloud compute instances create scalein-jobvm  \
  --zone=$zone --machine-type=f1-micro \
  --metadata-from-file startup-script=scaleinrun.sh


# 新增Pub/Sub ,cloud function
## 設定 default region
### 注意 Cloud Functions Locations 沒有台灣 asia-east1 不能使用 https://cloud.google.com/functions/docs/locations
gcloud config set functions/region asia-east2	

git clone https://github.com/harryliu123/devops-hands-on.git
cd GCE-scheduler-off-on
./deploy.sh

# 新增 scalein Cloud Scheduler : 建立啟動工作 每天19:30執行
## https://cloud.google.com/scheduler/docs/start-and-stop-compute-engine-instances-on-a-schedule?hl=zh-tw

gcloud beta scheduler jobs create pubsub scalein-jobvm \
    --schedule '30 19 * * 1,2,3,4,5' \
    --topic switcher \
    --message-body '{"switch": "on", "target": "scalein-jobvm"}' \
    --time-zone 'Asia/Taipei'
	
	
##################################################################################################################


#########################################
# 建立scaleout VM 所要執行的bash shell
#########################################
SIZE=3

cat <<EOF >> scaleoutrun.sh
#! /bin/bash
sudo su -
export CLOUD_SDK_REPO="cloud-sdk-$(lsb_release -c -s)"
echo "deb http://packages.cloud.google.com/apt $CLOUD_SDK_REPO main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
sudo apt-get update -y  && sudo apt-get install google-cloud-sdk -y
sudo apt-get install google-cloud-sdk-app-engine-java -y
touch sakey.json
EOF
echo "cat <<EOF >> sakey.json" >> scaleoutrun.sh
cat key.json >> scaleoutrun.sh
echo "EOF" >> scaleoutrun.sh

echo "gcloud auth activate-service-account $servicesa --key-file=sakey.json --project=$project" >> scaleoutrun.sh

echo "gcloud container clusters resize $CLUSTERNAME --node-pool default-pool --size $SIZE" >> scaleoutrun.sh

echo "init 0" >> scaleoutrun.sh

############################################


# 新增scaleout-jobvm VM

gcloud compute instances create scaleout-jobvm  \
  --zone=$zone --machine-type=f1-micro \
  --metadata-from-file startup-script=scaleoutrun.sh

# 新增 scaleout Cloud Scheduler : 建立啟動工作 每天8:00執行

gcloud beta scheduler jobs create pubsub scalein-jobvm \
    --schedule '0 8 * * 1,2,3,4,5' \
    --topic switcher \
    --message-body '{"switch": "on", "target": "scaleout-jobvm"}' \
    --time-zone 'Asia/Taipei'
	
###############################

