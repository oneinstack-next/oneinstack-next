#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
# BLOG:  https://linuxeye.com

Upgrade_Script() {
  echo 'Automatic self-update is unavailable until this project publishes verified release artifacts.' >&2
  echo 'Use a reviewed full commit from https://github.com/oneinstack-next/oneinstack-next in a separate checkout; preserve options.conf and follow docs/modernization.md.' >&2
  return 1
}
