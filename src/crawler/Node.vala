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

public enum NodeType
{
	DELETED,
	UNKNOWN,
	FILE,
	DIRECTORY,
	SYMLINK;
	
	public static NodeType from_file_type(FileType file_type)
	{
		switch (file_type)
		{
		case FileType.REGULAR:
			return FILE;
		case FileType.DIRECTORY:
			return DIRECTORY;
		case FileType.SYMBOLIC_LINK:
			return SYMLINK;
		default: // SPECIAL, SHORTCUT, MOUNTABLE, UNKNOWN, ...
			return UNKNOWN;
		}
	}
	
	public string to_string()
	{
		switch (this)
		{
		case DELETED:
			return "deleted";
		case FILE:
			return "file";
		case DIRECTORY:
			return "directory";
		case SYMLINK:
			return "symlink";
		default:
			return "unknown";
		}
	}
	
}

public class Node
{
	public static const string FILE_ATTRIBUTES = "standard::type,standard::name,standard::size,"
	+ "time::modified,time::modified-usec,unix::inode,unix::mode,unix::uid,unix::gid,"
	+ "xattr::*,xattr-sys::*";
	
	public NodeType node_type {get; private set;}
	public string name {get; private set;}
	public uint64 size {get; private set;}
	public DateTime mtime {get; private set;}
	public uint32 posix_mode {get; private set;}
	public uint32 posix_uid {get; private set;}
	public uint32 posix_gid {get; private set;}
	public uint64 posix_inode {get; private set;}
	public Bytes xattrs_hash {get; private set;}
	private HashTable<string, string> xattrs;
	
	public Node(NodeType type, string name, uint64 size, DateTime mtime, uint32 posix_mode, uint32 posix_uid,
		uint32 posix_gid, uint64 posix_inode, HashTable<string, string> xattrs)
	{
		this.node_type = type;
		this.name = name;
		this.size = size;
		this.mtime = mtime;
		this.posix_mode = posix_mode;
		this.posix_uid = posix_uid;
		this.posix_gid = posix_gid;
		this.posix_inode = posix_inode;
		this.xattrs = xattrs;
		hash_xattrs();
	}
	
	public static Node for_file(File file) throws GLib.Error
	{
		var info = file.query_info(FILE_ATTRIBUTES, FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
		return new Node.from_info(info);
	}
	
	public static async Node for_file_async(File file) throws GLib.Error
	{
		var info = yield file.query_info_async(FILE_ATTRIBUTES, FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, null);
		return new Node.from_info(info);
	}
	
	public Node.from_info(FileInfo info)
	{
		node_type = NodeType.from_file_type(info.get_file_type());
		name = info.get_name();
		size = info.get_attribute_uint64(FileAttribute.STANDARD_SIZE);
		mtime = new DateTime.from_timeval_local(info.get_modification_time());
		posix_mode = info.get_attribute_uint32(FileAttribute.UNIX_MODE);
		posix_uid = info.get_attribute_uint32(FileAttribute.UNIX_UID);
		posix_gid = info.get_attribute_uint32(FileAttribute.UNIX_GID);
		posix_inode = info.get_attribute_uint64(FileAttribute.UNIX_INODE);
		xattrs = new HashTable<string, string>(str_hash, str_equal);
		string[] xattr_namespaces = {"xattr", "xattr-sys"};
		foreach (unowned string xattr_ns in xattr_namespaces)
		{
			var xattr_names = info.list_attributes(xattr_ns);
			if (xattr_names != null)
				foreach (var name in xattr_names)
					xattrs[name] = info.get_attribute_string(name);
		}
		hash_xattrs();
	}
	
	private void hash_xattrs()
	{
		var type = GLib.ChecksumType.MD5;
		var checksum = new Checksum(type);
		var keys = xattrs.get_keys();
		keys.sort(strcmp);
		foreach (var key in keys)
		{
			checksum.update(key.data, -1);
			var val = xattrs[key];
			if (val != null && val != "")
				checksum.update(val.data, -1);
		}
		uint8[] buffer = new uint8[GLib.ChecksumType.MD5.get_length()];
		size_t size = (size_t) buffer.length;
		checksum.get_digest(buffer, ref size);
		buffer.length = (int) size;
		xattrs_hash = new Bytes.take((owned) buffer);
	}
	
	public bool is_symlink()
	{
		return node_type == NodeType.SYMLINK;
	}
	
	public bool is_file()
	{
		return node_type == NodeType.FILE;
	}
	
	public bool is_directory()
	{
		return node_type == NodeType.DIRECTORY;
	}
	
	public string to_string()
	{
		var buffer = new StringBuilder();
		buffer.append_printf("%s %04o %s %s %s.%06d %s:%s i%s",
			node_type.to_string(), posix_mode & 07777, name, human_file_size(size),
			mtime.format("%Y-%m-%d %H:%M:%S"), mtime.get_microsecond(),
			posix_uid.to_string(), posix_gid.to_string(), posix_inode.to_string());

		var keys = xattrs.get_keys();
		keys.sort(strcmp);
		foreach (unowned string key in keys)
			buffer.append_printf("\n%s: %s", key, xattrs[key]);

		return buffer.str;
	}
}

public const uint64 KIB = 0x0000000000400;
public const uint64 MIB = 0x0000000100000;
public const uint64 GIB = 0x0000040000000;
public const uint64 TIB = 0x0010000000000;
public const uint64 PIB = 0x4000000000000;

public string human_file_size(uint64 size)
{
	if (size >= PIB)
		return "%s.%03d PiB".printf((size/PIB).to_string(), (int)((size & (PIB-1))  * 1000 / PIB));
	if (size >= TIB)
		return "%s.%03d TiB".printf((size/TIB).to_string(), (int)((size & (TIB-1))  * 1000 / TIB));
	if (size >= GIB)
		return "%s.%03d GiB".printf((size/GIB).to_string(), (int)((size & (GIB-1)) * 1000 / GIB));
	if (size >= MIB)
		return "%s.%03d MiB".printf((size/MIB).to_string(), (int)((size & (MIB-1)) * 1000 / MIB));
	if (size >= KIB)
		return "%s.%03d KiB".printf((size/KIB).to_string(), (int)((size & (KIB-1)) * 1000 / KIB));
	return "%s B".printf(size.to_string());
}

} // namespace QuickSync

