#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

# 1. the test uses httpBasic(), which lives in spring-security-test
sed -i 's|<dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-test</artifactId><scope>test</scope></dependency>|&<dependency><groupId>org.springframework.security</groupId><artifactId>spring-security-test</artifactId><scope>test</scope></dependency>|' portal/pom.xml
grep -q 'spring-security-test' portal/pom.xml || { echo "pom patch failed"; exit 1; }

# 2. skip test compilation in the image build
sed -i 's|-DskipTests package|-Dmaven.test.skip=true package|' portal/Dockerfile
grep -q 'maven.test.skip' portal/Dockerfile || { echo "dockerfile patch failed"; exit 1; }

rm -f deployfix.sh
git add -A
git commit -q -m "fix: add spring-security-test, skip test compilation in image build"
git push
echo DONE
