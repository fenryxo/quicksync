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

public class TreeEnumerator
{
	public static const string FILE_ATTRIBUTES = "standard::type,standard::name,standard::size,"
	+ "time::modified,time::modified-usec,unix::inode,unix::mode,unix::uid,unix::gid,"
	+ "xattr::*,xattr-sys::*";
	
	public uint max_jobs  {get; set; default = 10;}
	public Cancellable cancellable {get; private set;}
	private Queue<File> dirs_queue;
	private bool running = false;
	private uint dirs_in_progress = 0;
	private string attributes;
	
	public TreeEnumerator(string attributes, Cancellable? cancellable=null)
	{
		this.attributes = attributes;
		this.cancellable = cancellable ?? new Cancellable();
		dirs_queue = new Queue<File>();
	}
	
	public signal void file_found(File file, FileInfo info);
	public signal void dir_found(File file, FileInfo info);
	public signal void link_found(File file, FileInfo info);
	public signal void special_found(File file, FileInfo info);
	public signal void error_occured(File dir, GLib.Error error);
	
	public void check_cancelled() throws GLib.IOError
	{
		if (cancellable.is_cancelled())
			throw new IOError.CANCELLED("Operation has been cancelled");
	}

	public void cancel()
	{
		cancellable.cancel();
	}
	
	public void reset()
	{
		cancellable.reset();
	}
	
	public void wait()
	{
		var loop = new MainLoop();
		Idle.add(() => {
			if (!running)
			{
				loop.quit();
				return false;
			}
			return true;
		});
		loop.run();
	}
	
	public void push_dir(File dir)
	{
		reset();
		dirs_queue.push_tail(dir);
		enumerate_dirs();
		
	}
	
	private void enumerate_dirs()
	{
		running = true;
		File? dir = null;
		while (dirs_in_progress < max_jobs && (dir = dirs_queue.pop_head()) != null)
		{
			dirs_in_progress++;
			enumerate_dir.begin(dir, on_enumerate_dir_done);
		}
		running = dirs_in_progress > 0 || !dirs_queue.is_empty();
	}
	
	private bool enumerate_next_dir()
	{
		var dir = dirs_queue.pop_head();
		if (dir == null)
			return false;
		enumerate_dir.begin(dir, on_enumerate_dir_done);
		return true;
	}
	
	private async void enumerate_dir(File dir) throws GLib.IOError
	{
		try
		{
			var listing = yield dir.enumerate_children_async(attributes,
				FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, cancellable);
			List<FileInfo> entries;
			while ((entries = yield listing.next_files_async(10, Priority.DEFAULT, cancellable)) != null)
			{
				foreach (var info in entries)
				{
					check_cancelled();
					var file = dir.get_child(info.get_name());
					switch (info.get_file_type())
					{
					case FileType.DIRECTORY:
						dir_found(file, info);
						push_dir(file);
						break;
					case FileType.REGULAR:
						file_found(file, info);
						break;
					case FileType.SYMBOLIC_LINK:
						link_found(file, info);
						break;
					default: // SPECIAL, SHORTCUT, MOUNTABLE, UNKNOWN, ...
						special_found(file, info);
						break;
					}
				}
			}
		}
		catch (GLib.IOError e1)
		{
			if (e1 is GLib.IOError.CANCELLED)
				throw e1;
			error_occured(dir, e1);
		}
		catch (GLib.Error e2)
		{
			error_occured(dir, e2);
		}
	}
	
	private void on_enumerate_dir_done(GLib.Object? o, AsyncResult res)
	{
		try
		{
			enumerate_dir.end(res);
			check_cancelled();
			if (enumerate_next_dir())
				return;
		}
		catch (GLib.IOError e)
		{
			assert(e is GLib.IOError.CANCELLED);
		}
		
		assert(dirs_in_progress > 0);
		dirs_in_progress--;
		running = dirs_in_progress > 0 || !dirs_queue.is_empty();
	}
}

} // namespace QuickSync
