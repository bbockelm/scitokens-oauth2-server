FROM hub.opensciencegrid.org/opensciencegrid/software-base:3.6-al8-release

RUN yum install -y curl java-11-openjdk java-11-openjdk-devel

# Download and install tomcat
RUN useradd -r -s /sbin/nologin tomcat ;\
mkdir -p /opt/tomcat ;\
curl -s -L https://archive.apache.org/dist/tomcat/tomcat-9/v9.0.69/bin/apache-tomcat-9.0.69.tar.gz | tar -zxf - -C /opt/tomcat --strip-components=1 ;\
chgrp -R tomcat /opt/tomcat/conf ;\
chmod g+rwx /opt/tomcat/conf ;\
chmod g+r /opt/tomcat/conf/* ;\
chown -R tomcat /opt/tomcat/logs/ /opt/tomcat/temp/ /opt/tomcat/webapps/ /opt/tomcat/work/ ;\
chgrp -R tomcat /opt/tomcat/bin /opt/tomcat/lib ;\
chmod g+rwx /opt/tomcat/bin ;\
chmod g+r /opt/tomcat/bin/*

ADD server.xml /opt/tomcat/conf/server.xml
RUN chgrp -R tomcat /opt/tomcat/conf/server.xml ;\
chmod go+r /opt/tomcat/conf/server.xml

ADD add-trust-root.pem /opt/tomcat/conf/add-trust-root.pem
ADD comodo-rsa.pem /opt/tomcat/conf/comodo-rsa.pem
ADD incommon-igtf.pem /opt/tomcat/conf/incommon-igtf.pem
RUN cat /opt/tomcat/conf/incommon-igtf.pem /opt/tomcat/conf/comodo-rsa.pem /opt/tomcat/conf/add-trust-root.pem > /opt/tomcat/conf/CA-bundle.pem && \
    keytool -cacerts -importcert -noprompt -storepass changeit -file /opt/tomcat/conf/incommon-igtf.pem -alias incommon && \
    keytool -cacerts -importcert -noprompt -storepass changeit -file /opt/tomcat/conf/comodo-rsa.pem -alias comodo && \
    keytool -cacerts -importcert -noprompt -storepass changeit -file /opt/tomcat/conf/add-trust-root.pem -alias addtrust

#ADD tomcat.service /etc/systemd/system/tomcat.service
#RUN systemctl enable tomcat.service

COPY --chown=tomcat:tomcat scitokens-server /opt
RUN curl -s -L https://github.com/ncsa/OA4MP/releases/download/v5.2.7.1/oauth2.war > /opt/tomcat/webapps/scitokens-server.war ;\
mkdir -p /opt/tomcat/webapps/scitokens-server ;\
cd /opt/tomcat/webapps/scitokens-server ;\
jar -xf ../scitokens-server.war ;\
chgrp -R tomcat /opt/tomcat/webapps/scitokens-server ;\
mkdir -p /opt/tomcat/var/storage/scitokens-server ;\
chown -R tomcat:tomcat /opt/tomcat/var/storage/scitokens-server ;\
rm -rf /opt/tomcat/webapps/ROOT /opt/tomcat/webapps/docs /opt/tomcat/webapps/examples /opt/tomcat/webapps/host-manager /opt/tomcat/webapps/manager
COPY --chown=tomcat:tomcat scitokens-server/web.xml /opt/tomcat/webapps/scitokens-server/WEB-INF/web.xml
RUN chmod 644 /opt/tomcat/webapps/scitokens-server/WEB-INF/web.xml

# need to put the java mail jar into the tomcat lib directory
RUN curl -s -L https://github.com/javaee/javamail/releases/download/JAVAMAIL-1_6_2/javax.mail.jar > /opt/tomcat/lib/javax.mail.jar

# Make JWK a volume mount
RUN mkdir -p /opt/scitokens-server/bin && mkdir -p /opt/scitokens-server/etc && mkdir -p /opt/scitokens-server/etc/templates && mkdir -p /opt/scitokens-server/lib && mkdir -p /opt/scitokens-server/log && mkdir -p /opt/scitokens-server/var/qdl/scitokens && mkdir -p /opt/scitokens-server/var/storage/file_store

# Create a single key in the etc directory for signing
RUN curl -s -L https://github.com/ncsa/OA4MP/releases/download/v5.2.7.1/jwt.jar > /opt/scitokens-server/lib/jwt.jar ;\
java -jar /opt/scitokens-server/lib/jwt.jar -batch create_keys -single -out /opt/scitokens-server/etc/keys.jwk ;\
chgrp tomcat /opt/scitokens-server/etc/keys.jwk ;\
chmod 640 /opt/scitokens-server/etc/keys.jwk

# Make server configuration a volume mount
ADD scitokens-server/etc/server-config.xml /opt/scitokens-server/etc/server-config.xml.tmpl
ADD scitokens-server/etc/proxy-config.xml /opt/scitokens-server/etc/proxy-config.xml.tmpl

ADD scitokens-server/bin/scitokens-cli /opt/scitokens-server/bin/scitokens-cli
RUN curl -L -s https://github.com/ncsa/OA4MP/releases/download/v5.2.7.1/oa2-cli.jar >/opt/scitokens-server/lib/scitokens-cli.jar ;\
chmod +x /opt/scitokens-server/bin/scitokens-cli

ADD scitokens-server/etc/templates/client-template.xml /opt/scitokens-server/etc/templates/client-template.xml
ADD scitokens-server/etc/templates/readme.txt /opt/scitokens-server/etc/templates/readme.txt
ADD scitokens-server/var/qdl/scitokens/policies.qdl /opt/scitokens-server/var/qdl/scitokens/policies.qdl
RUN chgrp tomcat /opt/scitokens-server/var/qdl/scitokens/policies.qdl
# Java 11 apparently does not identify the mime type for .json files quite right.
ADD scitokens-server/var/qdl/user-config.json /opt/scitokens-server/var/qdl/user-config.txt
RUN chgrp tomcat /opt/scitokens-server/var/qdl/user-config.txt
RUN ln -s /usr/lib64/libapr-1.so.0 /opt/tomcat/lib/libapr-1.so.0

ADD generate_jwk.sh /usr/local/bin/generate_jwk.sh

# QDL support 21-01-2021
RUN curl -L -s https://github.com/ncsa/OA4MP/releases/download/v5.2.7.1/oa2-qdl-installer.jar >/tmp/oa2-qdl-installer.jar ;\
java -jar /tmp/oa2-qdl-installer.jar -dir /opt/qdl

RUN  mkdir -p /opt/qdl/var/scripts

ADD qdl/etc/qdl.properties /opt/qdl/etc/qdl.properties
ADD qdl/etc/qdl-cfg.xml /opt/qdl/etc/qdl-cfg.xml

ADD qdl/var/scripts/boot.qdl /opt/qdl/var/scripts/boot.qdl
RUN chmod +x /opt/qdl/var/scripts/boot.qdl

ADD qdl/bin/qdl /opt/qdl/bin/qdl
RUN chmod +x /opt/qdl/bin/qdl

ADD qdl/bin/qdl-run /opt/qdl/bin/qdl-run
RUN chmod +x /opt/qdl/bin/qdl-run
# END QDL support

ENV JAVA_HOME=/usr/lib/jvm/jre
ENV CATALINA_PID=/opt/tomcat/temp/tomcat.pid
ENV CATALINA_HOME=/opt/tomcat
ENV CATALINA_BASE=/opt/tomcat
ENV CATALINA_OPTS="-Xms512M -Xmx1024M -server -XX:+UseParallelGC"
ENV JAVA_OPTS="-Djava.awt.headless=true -Djava.security.egd=file:/dev/./urandom -Djava.library.path=/opt/tomcat/lib"
ENV ST_HOME="/opt/scitokens-server"
ENV QDL_HOME="/opt/qdl"
ENV PATH="${ST_HOME}/bin:${QDL_HOME}/bin:${PATH}"

#RUN "${QDL_HOME}/var/scripts/boot.qdl"
ADD start.sh /start.sh
CMD ["/start.sh"]




