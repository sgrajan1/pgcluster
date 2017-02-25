VER=`cat version.txt`
sudo docker build -t evs-phoenix-postgres:$VER .
if [ $? -eq 0 ] ; then
 echo pushing to evs-r-docker.bebr.evs.tv private registry
 sudo docker tag -f evs-phoenix-postgres:$VER evs-r-docker.bebr.evs.tv:5000/evs-phoenix-postgres:$VER
 sudo docker push evs-r-docker.bebr.evs.tv:5000/evs-phoenix-postgres:$VER
fi