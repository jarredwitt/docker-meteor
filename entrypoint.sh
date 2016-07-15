#!/bin/bash
# Set default settings, pull repository, build
# app, etc., _if_ we are not given a different
# command.  If so, execute that command instead.
set -e

# Default values
: ${APP_DIR:="/var/www"}
: ${BRANCH:="master"}
: ${MONGO_URL:="mongodb://${MONGO_PORT_27017_TCP_ADDR}:${MONGO_PORT_27017_TCP_PORT}/${DB}"}
: ${PORT:="80"}

export MONGO_URL
export PORT

# If we were given arguments, run them instead
if [ $? -gt 1 ]; then
   exec "$@"
fi

# If we are provided a GITHUB_DEPLOY_KEY (path), then
# change it to the new, generic DEPLOY_KEY
if [ -n "${GITHUB_DEPLOY_KEY}" ]; then
   DEPLOY_KEY=$GITHUB_DEPLOY_KEY
fi

# If we are given a DEPLOY_KEY, copy it into /root/.ssh and
# setup a github rule to use it
if [ -n "${DEPLOY_KEY}" ]; then
   if [ ! -f /root/.ssh/deploy_key ]; then
      mkdir -p /root/.ssh
      cp ${DEPLOY_KEY} /root/.ssh/deploy_key
      cat << ENDHERE >> /root/.ssh/config
Host *
  IdentityFile /root/.ssh/deploy_key
  StrictHostKeyChecking no
ENDHERE
   fi
fi

mkdir -p /usr/src

if [ -n "${REPO}" ]; then
   if [ -e /usr/src/app/.git ]; then
      pushd /usr/src/app
      echo "Updating local repository..."
      git fetch
      popd
   else
      echo "Getting ${REPO}..."
      git clone ${REPO} /usr/src/app
   fi

   cd /usr/src/app

   echo "Switching to branch/tag ${BRANCH}..."
   git checkout ${BRANCH}

   echo "Forcing clean..."
   git reset --hard origin/${BRANCH}
   git clean -d -f
   pushd /usr/src/app

   # Find the meteor installation within the repo
   METEOR_DIR=$(find ./ -type d -name .meteor -print |head -n1)
   if [ ! -n "${METEOR_DIR}" ]; then
      echo "Failed to locate Meteor path"
      exit 1;
   fi
   cd ${METEOR_DIR}/..

   # Bundle the Meteor app
   echo "Building the bundle..."
   mkdir -p ${APP_DIR}
   set +e # Allow the next command to fail
   meteor build --directory ${APP_DIR}
   if [ $? -ne 0 ]; then
      echo "Building the bundle (old version)..."
      set -e
      # Old versions used 'bundle' and didn't support the --directory option
      meteor bundle bundle.tar.gz
      tar xf bundle.tar.gz -C ${APP_DIR}
   fi
   set -e
fi

if [ -n "${BUNDLE_URL}" ]; then
   echo "Getting Meteor bundle..."
   curl -o /tmp/bundle.tgz ${BUNDLE_URL}
   tar xf /tmp/bundle.tgz -C ${APP_DIR}
fi

# See if the actual bundle is in the bundle
# subdirectory (default)
if [ -d ${APP_DIR}/bundle ]; then
   APP_DIR=${APP_DIR}/bundle
else
	tar xf ${APP_DIR}/bundle.tar.gz --no-same-owner -C ${APP_DIR}
fi

# Install NPM modules
if [ -e ${APP_DIR}/programs/server ]; then
   echo "Installing NPM prerequisites..."
   rm -r -f ${APP_DIR}/programs/server/npm/node_modules/meteor/npm-bcrypt/node_modules/bcrypt
   cd ${APP_DIR}/programs/server/npm/node_modules/meteor/npm-bcrypt
   npm install bcrypt
   pushd ${APP_DIR}/programs/server/
   npm install
   popd
else
   echo "Unable to locate server directory; hold on: we're likely to fail"
fi

# Run meteor
cd ${APP_DIR}
cat /etc/hosts
echo "Starting Meteor..."
exec node ./main.js
