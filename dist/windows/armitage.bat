@echo off
set BASE=%~dp0
cd "%BASE%"
set PATH=%BASE%ruby\bin;%BASE%java\bin;%BASE%tools;%BASE%tools\svn\bin;%BASE%nmap;%BASE%postgresql\bin;%PATH%
set JAVA_HOME=%BASE%java
cd "%BASE%msf3"
start rubyw armitage -y "%BASE%config\database.yml"
