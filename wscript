#!/usr/bin/env python
# encoding: utf-8
#
# Copyright 2014 Jiří Janoušek <janousek.jiri@gmail.com>
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met: 
# 
# 1. Redistributions of source code must retain the above copyright notice, this
#    list of conditions and the following disclaimer. 
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution. 
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
# ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

# Top of source tree
top = '.'
# Build directory
out = 'build'

# Application name and version
NAME="Quick Sync"
APPNAME = "quicksync"
APP_NAMESPACE = "QUICK_SYNC"
VERSION = "0.1.0+"
UNIQUE_NAME="cz.fenryxo.QuickSync"
GENERIC_NAME = "File synchronizer"
BLURB = "File synchronization tool"

import subprocess
try:
	try:
		# Read revision info from file revision-info created by ./waf dist
		short_id, long_id = open("revision-info", "r").read().split(" ", 1)
	except Exception, e:
		# Read revision info from current branch
		output = subprocess.Popen(["git", "log", "-n", "1", "--pretty=format:%h %H"], stdout=subprocess.PIPE).communicate()[0]
		short_id, long_id = output.split(" ", 1)
except Exception, e:
	short_id, long_id = "fuzzy_id", "fuzzy_id"

REVISION_ID = str(long_id).strip()


VERSIONS, VERSION_SUFFIX = VERSION.split("+")
if VERSION_SUFFIX == "stable":
	VERSION = VERSIONS
elif VERSION_SUFFIX == "":
	from datetime import datetime
	suffix = "{}.{}".format(datetime.utcnow().strftime("%Y%m%d%H%M"), short_id)
	VERSION_SUFFIX += suffix
	VERSION += suffix
VERSIONS = map(int, VERSIONS.split("."))

import sys
from waflib.Configure import conf
from waflib.Errors import ConfigurationError
from waflib.Context import WAFVERSION

WAF_VERSION = map(int, WAFVERSION.split("."))
REQUIRED_VERSION = [1, 7, 14] 
if WAF_VERSION < REQUIRED_VERSION:
	print("Too old waflib %s < %s. Use waf binary distributed with the source code!" % (WAF_VERSION, REQUIRED_VERSION))
	sys.exit(1)

@conf
def vala_def(ctx, vala_definition):
	"""Appends a Vala definition"""
	if not hasattr(ctx.env, "VALA_DEFINES"):
		ctx.env.VALA_DEFINES = []
	if isinstance(vala_def, tuple) or isinstance(vala_def, list):
		for d in vala_definition:
			ctx.env.VALA_DEFINES.append(d)
	else:
		ctx.env.VALA_DEFINES.append(vala_definition)

@conf
def check_dep(ctx, pkg, uselib, version, mandatory=True, store=None, vala_def=None, define=None):
	"""Wrapper for ctx.check_cfg."""
	result = True
	try:
		res = ctx.check_cfg(package=pkg, uselib_store=uselib, atleast_version=version, mandatory=True, args = '--cflags --libs')
		if vala_def:
			ctx.vala_def(vala_def)
		if define:
			for key, value in define.iteritems():
				ctx.define(key, value)
	except ConfigurationError, e:
		result = False
		if mandatory:
			raise e
	finally:
		if store is not None:
			ctx.env[store] = result
	return res

# Add extra options to ./waf command
def options(ctx):
	ctx.load('compiler_c vala')
	ctx.add_option('--noopt', action='store_true', default=False, dest='noopt', help="Turn off compiler optimizations")
	ctx.add_option('--debug', action='store_true', default=True, dest='debug', help="Turn on debugging symbols")
	ctx.add_option('--no-debug', action='store_false', dest='debug', help="Turn off debugging symbols")
	ctx.add_option('--no-system-hooks', action='store_false', default=True, dest='system_hooks', help="Don't run system hooks after installation (ldconfig, icon cache update, ...")

# Configure build process
def configure(ctx):
	ctx.msg("Revision id", REVISION_ID, "GREEN")
	ctx.env.VALA_DEFINES = []
	ctx.msg('Install prefix', ctx.options.prefix, "GREEN")
	ctx.load('compiler_c vala')
	ctx.check_vala(min_version=(0,22,1))
	# Don't be quiet
	ctx.env.VALAFLAGS.remove("--quiet")
	ctx.env.append_value("VALAFLAGS", "-v")
	
	# enable threading
	ctx.env.append_value("VALAFLAGS", "--thread")
	
	# Turn compiler optimizations on/off
	if ctx.options.noopt:
		ctx.msg('Compiler optimizations', "OFF?!", "RED")
		ctx.env.append_unique('CFLAGS', '-O0')
	else:
		ctx.env.append_unique('CFLAGS', '-O2')
		ctx.msg('Compiler optimizations', "ON", "GREEN")
	
	# Include debugging symbols
	if ctx.options.debug:
		#~ ctx.env.append_unique('VALAFLAGS', '-g')
		ctx.env.append_unique('CFLAGS', '-g3')
	
	# Anti-underlinking and anti-overlinking linker flags.
	ctx.env.append_unique("LINKFLAGS", ["-Wl,--no-undefined", "-Wl,--as-needed"])
	
	# Check dependencies
	ctx.env.DIORITE_SERIES = DIORITE_SERIES = "0.1"
	ctx.check_dep('glib-2.0', 'GLIB', '2.32')
	ctx.check_dep('gio-2.0', 'GIO', '2.32')
	ctx.check_dep('gtk+-3.0', 'GTK+', '3.4')
	ctx.check_dep('gdk-3.0', 'GDK', '3.4')
	ctx.check_dep('gthread-2.0', 'GTHREAD', '2.32')
	ctx.check_dep('dioriteglib-' + DIORITE_SERIES, 'DIORITEGLIB', DIORITE_SERIES)
	ctx.check_dep('dioritegtk-' + DIORITE_SERIES, 'DIORITEGTK', DIORITE_SERIES)
	
	ctx.define("%s_APPNAME" % APP_NAMESPACE, APPNAME)
	ctx.define("%s_NAME" % APP_NAMESPACE, NAME)
	ctx.define("%s_UNIQUE_NAME" % APP_NAMESPACE, UNIQUE_NAME)
	ctx.define("%s_APP_ICON" % APP_NAMESPACE, APPNAME)
	ctx.define("%s_VERSION" % APP_NAMESPACE, VERSION)
	ctx.define("%s_REVISION" % APP_NAMESPACE, REVISION_ID)
	ctx.define("%s_VERSION_MAJOR" % APP_NAMESPACE, VERSIONS[0])
	ctx.define("%s_VERSION_MINOR" % APP_NAMESPACE, VERSIONS[1])
	ctx.define("%s_VERSION_BUGFIX" % APP_NAMESPACE, VERSIONS[2])
	ctx.define("%s_VERSION_SUFFIX" % APP_NAMESPACE, VERSION_SUFFIX)
	ctx.define("GETTEXT_PACKAGE", "quicksync")

def build(ctx):
	#~ print ctx.env
	vala_defines = ctx.env.VALA_DEFINES
	CFLAGS=""
	
	HELLO = "hello"
	CRAWLER="crawler"
	packages = 'dioritegtk-{0} dioriteglib-{0} '.format(ctx.env.DIORITE_SERIES)
	packages += 'gtk+-3.0 gdk-3.0 glib-2.0 gio-2.0'
	uselib = 'DIORITEGTK DIORITEGLIB GTK+ GDK GLIB GTHREAD GIO'
	
	ctx.program(
		target = HELLO,
		source = ctx.path.ant_glob('src/%s/*.vala' % HELLO),
		packages = packages,
		uselib = uselib,
		vala_defines = vala_defines,
		defines = ['G_LOG_DOMAIN="%s"' % HELLO],
		vapi_dirs = ['vapi'],
		vala_target_glib = "2.32",
	)
	
	ctx.program(
		target = "%s-%s" % (APPNAME, CRAWLER),
		source = ctx.path.ant_glob('src/%s/*.vala' % CRAWLER),
		packages = packages,
		uselib = uselib,
		vala_defines = vala_defines,
		defines = ['G_LOG_DOMAIN="%s"' % CRAWLER],
		vapi_dirs = ['vapi'],
		vala_target_glib = "2.32",
	)
	

def dist(ctx):
	ctx.algo = "tar.gz"
	ctx.excl = '.git .gitignore build/* **/.waf* **/*~ **/*.swp **/.lock* bzrcommit.txt **/*.pyc'
	ctx.exec_command("git log -n 1 --pretty='format:%h %H' > revision-info")
	
	def archive():
		ctx._archive()
		node = ctx.path.find_node("revision-info")
		if node:
			node.delete()
	ctx._archive = ctx.archive
	ctx.archive = archive

from waflib.TaskGen import extension
@extension('.vapi')
def vapi_file(self, node):
	try:
		valatask = self.valatask
	except AttributeError:
		valatask = self.valatask = self.create_task('valac')
		self.init_vala_task()

	valatask.inputs.append(node)
