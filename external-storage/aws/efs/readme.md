
EFS create
---
https://github.com/stelligent/cloudformation_templates/tree/master/storage


provisioner EFS create
---
git clone https://github.com/harryliu123/devops-hands-on
cd external-storage/aws/efs/

請修改 deploy.yaml

  file.system.id: fs-218dd98a
  aws.region: us-west-2
  provisioner.name: systex.com/aws-efs
  dns.name: fs-218dd98a.efs.us-west-2.amazonaws.com
  
  server: fs-218dd98a.efs.us-west-2.amazonaws.com
  
  provisioner: systex.com/aws-efs
  
  ------
  
 
 kubectl apply -f deploy.yaml
