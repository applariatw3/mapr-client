FROM applariat/mapr-base:centos6
#Starting from mapr base image

ARG artifact_root="."
#Additional build args from AppLariat component configuration will be inserted dynamically

#Copy files into place
COPY $artifact_root/build.sh /build.sh
COPY $artifact_root/entrypoint.sh /entrypoint.sh
COPY $artifact_root/code/ /code/

#Install mapr packages
RUN chmod +x /build.sh /entrypoint.sh
RUN /build.sh 

EXPOSE 22

ENTRYPOINT ["/entrypoint.sh"]

CMD ["/usr/sbin/sshd", "-D"]
