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

public delegate void FileHashReadyCallback(File file, string? hash, GLib.Error? error);

public class FileHasher : GLib.Object
{
	private static const int BUFFER_SIZE = 4096;
	
	public static async string hash_file(ChecksumType checksum_type, File file, Cancellable? cancellable=null) throws Error
	{
		var input = yield file.read_async(Priority.DEFAULT, cancellable);
		var checksum = new Checksum(checksum_type);
		uint8[] buffer = new uint8[BUFFER_SIZE];
		while (true)
		{
			var bytes_read = yield input.read_async(buffer, Priority.DEFAULT, cancellable);
			if (bytes_read == 0)
				break;
			checksum.update(buffer, bytes_read);
		}
		return checksum.get_string();
	}
	
	public static string hash_file_sync(ChecksumType checksum_type, File file, Cancellable? cancellable=null) throws Error
	{
		var input = file.read(cancellable);
		var checksum = new Checksum(checksum_type);
		uint8[] buffer = new uint8[BUFFER_SIZE];
		while (true)
		{
			var bytes_read = input.read(buffer, cancellable);
			if (bytes_read == 0)
				break;
			checksum.update(buffer, bytes_read);
		}
		return checksum.get_string();
	}
	
	private int _max_jobs = 5;
	public int max_jobs
	{
		get
		{
			return _max_jobs;
		}
		set
		{
			_max_jobs = value;
			lock (workers)
			{
				if (workers != null)
				{
					try
					{
						workers.set_max_threads(_max_jobs);
					}
					catch (ThreadError e)
					{
						critical("Unexpected error: %s", e.message);
					}
				}
			}
		}
	}
	
	public ChecksumType checksum_type {get; private set;}
	private Queue<Task> queue;
	private ThreadPool<Task> workers = null;
	private uint jobs_in_progress = 0;
	
	public bool running
	{
		get
		{
			bool running;
			lock (workers)
			{
				lock(jobs_in_progress)
				{
					running = workers != null && workers.unprocessed() > 0 || jobs_in_progress > 0;
				}
			}
			return running;
		}
	}
	
	public FileHasher(ChecksumType checksum_type)
	{
		this.checksum_type = checksum_type;
		queue = new Queue<Task>();
	}
	
	public bool push_file(File file, owned FileHashReadyCallback callback, Cancellable? cancellable=null)
	{
		if (!Thread.supported())
			return false;
			
		lock (workers)
		{
			try
			{
				if (workers == null)
					workers = new ThreadPool<Task>.with_owned_data(worker_func, max_jobs, false);
			
				workers.add(new Task(file, (owned) callback, cancellable));
			}
			catch (ThreadError e)
			{
				critical("Unexpected error: %s", e.message);
				return false;
			}
		}
		return true;
	}
	
	public void wait()
	{
		lock (workers)
		{
			if (workers == null)
				return;
		}
		
		var loop = new MainLoop();
		Idle.add(() =>
		{
			if (!running)
				loop.quit();
			return running;
		});
		loop.run();
	}
	
	private void worker_func(owned Task task)
	{
		lock (jobs_in_progress)
			jobs_in_progress++;
		
		try
		{
			task.check_cancelled();
			task.hash = hash_file_sync(checksum_type, task.file, task.cancellable);
		}
		catch (GLib.Error e)
		{
			task.error = e;
		}
		
		Idle.add(task.callback_source_func);
		
		lock (jobs_in_progress)
			jobs_in_progress--;
	}
	
	private class Task
	{
		public File file;
		public FileHashReadyCallback callback;
		public Cancellable? cancellable;
		public string? hash = null;
		public GLib.Error? error = null;
		
		public Task(File file, owned FileHashReadyCallback callback, Cancellable? cancellable=null)
		{
			this.file = file;
			this.callback = (owned) callback;
			this.cancellable = cancellable;
		}
		
		public bool callback_source_func()
		{
			callback(file, hash, error);
			return false;
		}
		
		public void check_cancelled() throws GLib.IOError
		{
			if (cancellable != null && cancellable.is_cancelled())
				throw new IOError.CANCELLED("Hashing task has been cancelled");
		}
	}
}

} // namespace QuickSync
