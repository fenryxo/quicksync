/*
 * Copyright 2015 Jiří Janoušek <janousek.jiri@gmail.com>
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met: 
 * 
 * 1. Redistributions of source code must retain the above copyright notice, this
 *    list of conditions and the following disclaimer. 
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution. 
 * 
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
 * ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

namespace QuickSync
{

struct Args
{
	static bool debug;
	static bool verbose;
	static string? log_file = null;
	
	public static const OptionEntry[] options =
	{
		{ "verbose", 'v', 0, OptionArg.NONE, ref Args.verbose, "Print informational messages", null },
		{ "debug", 'D', 0, OptionArg.NONE, ref Args.debug, "Print debugging messages", null },
		{ "log-file", 'L', 0, OptionArg.FILENAME, ref Args.log_file, "Log to file", "FILE" },
		{ null }
	};
}

public int main(string[] args)
{
	try
	{
		var opt_context = new OptionContext("");
		opt_context.set_help_enabled(true);
		opt_context.add_main_entries(Args.options, null);
		opt_context.set_ignore_unknown_options(true);
		opt_context.parse(ref args);
	}
	catch (OptionError e)
	{
		stderr.printf("option parsing failed: %s\n", e.message);
		return 1;
	}
	
	FileStream? log = null;
	if (Args.log_file != null)
	{
		log = FileStream.open(Args.log_file, "w");
		if (log == null)
		{
			stderr.printf("Cannot open log file '%s' for writting.\n", Args.log_file);
			return 1;
		}
	}
	
	Diorite.Logger.init(log != null ? log : stderr, Args.debug ? GLib.LogLevelFlags.LEVEL_DEBUG
	 : (Args.verbose ? GLib.LogLevelFlags.LEVEL_INFO: GLib.LogLevelFlags.LEVEL_WARNING));
	
	if (args.length < 2)
	{
		stderr.printf("Error: Not enough arguments.\n");
		return 1;
	}
	
	var target_dir = File.new_for_path(args[1]);
	if (!target_dir.query_exists())
	{
		stderr.printf("Error: The directory %s doesn't exist.\n", target_dir.get_path());
		return 1;
	}
	
	
	var cancellable = new Cancellable();
	enumerate(target_dir, cancellable);
	return 0;
}

void enumerate(File dir, Cancellable? cancellable=null)
{
	message("%s", dir.get_path());
	var enumerator = new TreeEnumerator(TreeEnumerator.FILE_ATTRIBUTES, cancellable);
	enumerator.error_occured.connect(on_error_occured);
	enumerator.dir_found.connect(on_node_found);
	enumerator.file_found.connect(on_node_found);
	enumerator.link_found.connect(on_node_found);
	enumerator.special_found.connect(on_node_found);
	enumerator.push_dir(dir);
	enumerator.wait();
}

void on_error_occured(TreeEnumerator enumerator, File dir, GLib.Error e)
{
	warning("%s: %s", dir.get_path(), e.message);
}

void on_node_found(TreeEnumerator enumerator, File file, FileInfo info)
{
	message("%s", file.get_path());
}

} // namespace QuickSync

