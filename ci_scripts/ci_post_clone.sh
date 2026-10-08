#!/bin/sh

#  ci_post_clone.sh
#  Hamster
#
#  Created by morse on 2023/9/28.
#  
set -e

ROOT="${CI_PRIMARY_REPOSITORY_PATH:?CI_PRIMARY_REPOSITORY_PATH is required}"
bash "$ROOT/librimeFramework.sh"
bash "$ROOT/InputSchemaBuild.sh"
