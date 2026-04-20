FROM tomcat:10.1-jdk17
# Copy your war file to the webapps directory
COPY target/*.war /usr/local/tomcat/webapps
EXPOSE 8080
CMD ["catalina.sh", "run"]
