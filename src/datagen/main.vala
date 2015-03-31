/*
 * Copyright 2014 Jiří Janoušek <janousek.jiri@gmail.com>
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
	 : (Args.verbose ? GLib.LogLevelFlags.LEVEL_INFO: GLib.LogLevelFlags.LEVEL_WARNING),
	 "datagen");
	
	if (args.length < 2)
	{
		stderr.printf("Error: Not enough arguments.\n");
		return 1;
	}
	
	var target_dir = File.new_for_path(args[1]);
	if (target_dir.query_exists())
	{
		stderr.printf("Error: The directory %s already exists.\n", target_dir.get_path());
		return 1;
	}
	
	debug("Hello Debug. %d", args.length);
	message("Hello Info.");
	stdout.puts("Hello!\n");
	
	var data_gen = new DataGen(target_dir, 6, 10);
	try
	{
		data_gen.generate_sync();
	}
	catch (GLib.Error e)
	{
		warning("%s", e.message);
	}
	
	return 0;
}

class DataGen : GLib.Object
{
	private File root_dir;
//~ 	private int32 factor;
	private Rand random;
	private int depth;
	private int width;
	
	public DataGen(File root_dir, int depth, int width)
	{
		this.root_dir = root_dir;
//~ 		this.factor = factor;
		this.depth = depth;
		this.width = width;
		random = new Rand.with_seed(1);
	}
	
	public void generate_sync() throws GLib.Error
	{
		GLib.Error? async_error = null;
		var loop = new MainLoop();
		generate.begin((o, res) =>
		{
			try
			{
				generate.end(res);
			}
			catch (GLib.Error e)
			{
				async_error = e;
			}
			loop.quit();
		});
		loop.run();
		
		if (async_error != null)
			throw async_error;
	}
	
	public async void generate() throws GLib.Error
	{
		Idle.add(generate.callback);
		debug("mkdir %s", root_dir.get_path());
		root_dir.make_directory_with_parents();
		yield generate_dirs(root_dir, depth, width);
	}
	
	private async void generate_dirs(File dir, int depth, int width)
	{
//~ 		var new_factor = factor / 2;
		var child_depth = depth - 1;
		var child_width = width + 1;
		var n_dirs = (int) random.int_range(0, (int32) width);
		var n_files = (int) random.int_range(0, (int32) width);
		
		for (var i = 0; i < n_dirs; i++)
		{
//~ 			var dice = random.int_range(0, factor + 1);
//~ 			message("Dice: %s", dice.to_string());
//~ 			if (dice == 0)
//~ 				continue;
			var child = dir.get_child("dir%d".printf(i));
			debug("mkdir %s", child.get_path());
			try
			{
//~ 				yield child.make_directory_async();
				child.make_directory();
				if (child_depth > 0)
					yield generate_dirs(child, child_depth, child_width);
			}
			catch (GLib.Error e)
			{
				warning("%s", e.message);
			}
			
		}
		
		for (var i = 0; i < n_files; i++)
		{
			var child = dir.get_child("file%d.txt".printf(i));
			var data = random.int_range(0, 100).to_string();
			debug("write %s > %s", data, child.get_path());
			try
			{
//~ 				var output = yield child.create_async(FileCreateFlags.NONE, Priority.DEFAULT, null);
				var output = child.create(FileCreateFlags.NONE, null);
				output.write_all(data.data, null, null);
			}
			catch (GLib.Error e)
			{
				warning("%s", e.message);
			}
		}
	}
}

} // namespace QuickSync

