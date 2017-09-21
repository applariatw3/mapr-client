FROM applariat/mapr-base:5.2.2_3.0.1
#Starting from mapr base image

ARG MAPR_BUILD
ENV MAPR_BUILD=${MAPR_BUILD:-"yarn"}
ENV MAPR_PORTS=22 MAPR_MONITORING=false MAPR_LOGGING=false
ENV container docker

#Copy files into place
COPY authorized_keys /tmp/
COPY build.sh entrypoint.sh /

#Install mapr packages
RUN /build.sh
#RUN /opt/mapr/installer/docker/mapr-setup.sh -r http://package.mapr.com/releases container core 

EXPOSE $MAPR_PORTS

ENTRYPOINT ["/entrypoint.sh"]

CMD ["/usr/bin/supervisord","-c","/etc/supervisor/conf.d/supervisord.conf"]
