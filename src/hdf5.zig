const std = @import("std");

// HDF5 C types
pub const hid_t = i64;
pub const hsize_t = u64;
pub const herr_t = c_int;

pub const Error = error{HDF5Error};

// ---------------------------------------------------------------------------
// Extern globals (only valid after init())
// ---------------------------------------------------------------------------
extern var H5T_NATIVE_DOUBLE_g: hid_t;
extern var H5T_C_S1_g: hid_t;
extern var H5P_CLS_DATASET_CREATE_ID_g: hid_t;

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------
pub const H5P_DEFAULT: hid_t = 0;
pub const H5S_ALL: hid_t = 0;
pub const H5F_ACC_TRUNC: c_uint = 0x0002;
pub const H5S_SCALAR: c_int = 0;
pub const H5S_SELECT_SET: c_int = 0;
pub const H5S_UNLIMITED: hsize_t = std.math.maxInt(u64);
pub const H5T_VARIABLE: usize = std.math.maxInt(usize);

// ---------------------------------------------------------------------------
// C function declarations
// ---------------------------------------------------------------------------
extern fn H5open() herr_t;
extern fn H5Fcreate(filename: [*:0]const u8, flags: c_uint, fcpl_id: hid_t, fapl_id: hid_t) hid_t;
extern fn H5Fclose(file_id: hid_t) herr_t;
extern fn H5Gcreate2(loc_id: hid_t, name: [*:0]const u8, lcpl_id: hid_t, gcpl_id: hid_t, gapl_id: hid_t) hid_t;
extern fn H5Gclose(group_id: hid_t) herr_t;
extern fn H5Dcreate2(loc_id: hid_t, name: [*:0]const u8, type_id: hid_t, space_id: hid_t, lcpl_id: hid_t, dcpl_id: hid_t, dapl_id: hid_t) hid_t;
extern fn H5Dwrite(dset_id: hid_t, mem_type_id: hid_t, mem_space_id: hid_t, file_space_id: hid_t, dxpl_id: hid_t, buf: ?*const anyopaque) herr_t;
extern fn H5Dset_extent(dset_id: hid_t, size: [*]const hsize_t) herr_t;
extern fn H5Dget_space(dset_id: hid_t) hid_t;
extern fn H5Dclose(dset_id: hid_t) herr_t;
extern fn H5Screate(class: c_int) hid_t;
extern fn H5Screate_simple(rank: c_int, dims: [*]const hsize_t, maxdims: ?[*]const hsize_t) hid_t;
extern fn H5Sselect_hyperslab(space_id: hid_t, op: c_int, start: [*]const hsize_t, stride: ?[*]const hsize_t, count: [*]const hsize_t, block_: ?[*]const hsize_t) herr_t;
extern fn H5Sclose(space_id: hid_t) herr_t;
extern fn H5Acreate2(loc_id: hid_t, attr_name: [*:0]const u8, type_id: hid_t, space_id: hid_t, acpl_id: hid_t, aapl_id: hid_t) hid_t;
extern fn H5Awrite(attr_id: hid_t, type_id: hid_t, buf: ?*const anyopaque) herr_t;
extern fn H5Aclose(attr_id: hid_t) herr_t;
extern fn H5Tcopy(type_id: hid_t) hid_t;
extern fn H5Tset_size(type_id: hid_t, size: usize) herr_t;
extern fn H5Tclose(type_id: hid_t) herr_t;
extern fn H5Pcreate(cls_id: hid_t) hid_t;
extern fn H5Pset_chunk(plist_id: hid_t, ndims: c_int, dim: [*]const hsize_t) herr_t;
extern fn H5Pclose(plist_id: hid_t) herr_t;

// ---------------------------------------------------------------------------
// Initialization — must be called before accessing extern globals
// ---------------------------------------------------------------------------
var initialized: bool = false;

pub fn init() Error!void {
    if (!initialized) {
        if (H5open() < 0) return error.HDF5Error;
        initialized = true;
    }
}

// ---------------------------------------------------------------------------
// File handle
// ---------------------------------------------------------------------------
pub const File = struct {
    id: hid_t,

    pub fn create(path: [:0]const u8) Error!File {
        try init();
        const fid = H5Fcreate(path.ptr, H5F_ACC_TRUNC, H5P_DEFAULT, H5P_DEFAULT);
        if (fid < 0) return error.HDF5Error;
        return .{ .id = fid };
    }

    pub fn close(self: File) void {
        _ = H5Fclose(self.id);
    }

    pub fn createGroup(self: File, name: [:0]const u8) Error!Group {
        return Group.create(self.id, name);
    }
};

// ---------------------------------------------------------------------------
// Group handle
// ---------------------------------------------------------------------------
pub const Group = struct {
    id: hid_t,

    pub fn create(parent: hid_t, name: [:0]const u8) Error!Group {
        const gid = H5Gcreate2(parent, name.ptr, H5P_DEFAULT, H5P_DEFAULT, H5P_DEFAULT);
        if (gid < 0) return error.HDF5Error;
        return .{ .id = gid };
    }

    pub fn close(self: Group) void {
        _ = H5Gclose(self.id);
    }

    pub fn createGroup(self: Group, name: [:0]const u8) Error!Group {
        return Group.create(self.id, name);
    }
};

// ---------------------------------------------------------------------------
// Chunked 1-D f64 dataset — supports unlimited append
// ---------------------------------------------------------------------------
pub const CHUNK_ROWS: u64 = 4096;

pub const ChunkedDataset = struct {
    id: hid_t,
    current_rows: u64,

    pub fn create(parent: hid_t, name: [:0]const u8, chunk_size: u64) Error!ChunkedDataset {
        // Property list with chunking enabled
        const plist = H5Pcreate(H5P_CLS_DATASET_CREATE_ID_g);
        if (plist < 0) return error.HDF5Error;
        defer _ = H5Pclose(plist);

        const chunk_dims = [_]hsize_t{chunk_size};
        if (H5Pset_chunk(plist, 1, &chunk_dims) < 0) return error.HDF5Error;

        // Start at 0 rows, allow unlimited growth
        const init_dims = [_]hsize_t{0};
        const max_dims = [_]hsize_t{H5S_UNLIMITED};
        const space = H5Screate_simple(1, &init_dims, &max_dims);
        if (space < 0) return error.HDF5Error;
        defer _ = H5Sclose(space);

        const did = H5Dcreate2(
            parent,
            name.ptr,
            H5T_NATIVE_DOUBLE_g,
            space,
            H5P_DEFAULT,
            plist,
            H5P_DEFAULT,
        );
        if (did < 0) return error.HDF5Error;

        return .{ .id = did, .current_rows = 0 };
    }

    /// Append rows of f64 data to the dataset, extending it as needed.
    pub fn appendRows(self: *ChunkedDataset, data: []const f64) Error!void {
        if (data.len == 0) return;

        const new_total = self.current_rows + data.len;
        const new_dims = [_]hsize_t{new_total};
        if (H5Dset_extent(self.id, &new_dims) < 0) return error.HDF5Error;

        // Select the appended region in file space
        const file_space = H5Dget_space(self.id);
        if (file_space < 0) return error.HDF5Error;
        defer _ = H5Sclose(file_space);

        const start = [_]hsize_t{self.current_rows};
        const count = [_]hsize_t{data.len};
        if (H5Sselect_hyperslab(file_space, H5S_SELECT_SET, &start, null, &count, null) < 0)
            return error.HDF5Error;

        // Memory space matching the block size
        const mem_space = H5Screate_simple(1, &count, null);
        if (mem_space < 0) return error.HDF5Error;
        defer _ = H5Sclose(mem_space);

        if (H5Dwrite(self.id, H5T_NATIVE_DOUBLE_g, mem_space, file_space, H5P_DEFAULT, @ptrCast(data.ptr)) < 0)
            return error.HDF5Error;

        self.current_rows = new_total;
    }

    pub fn close(self: ChunkedDataset) void {
        _ = H5Dclose(self.id);
    }
};

// ---------------------------------------------------------------------------
// Attribute helpers
// ---------------------------------------------------------------------------

/// Write a variable-length string attribute on any HDF5 object.
pub fn writeStringAttr(loc_id: hid_t, name: [:0]const u8, value: [:0]const u8) Error!void {
    const str_type = H5Tcopy(H5T_C_S1_g);
    if (str_type < 0) return error.HDF5Error;
    defer _ = H5Tclose(str_type);
    if (H5Tset_size(str_type, H5T_VARIABLE) < 0) return error.HDF5Error;

    const space = H5Screate(H5S_SCALAR);
    if (space < 0) return error.HDF5Error;
    defer _ = H5Sclose(space);

    const attr = H5Acreate2(loc_id, name.ptr, str_type, space, H5P_DEFAULT, H5P_DEFAULT);
    if (attr < 0) return error.HDF5Error;
    defer _ = H5Aclose(attr);

    // HDF5 variable-length strings: write through pointer-to-pointer
    var c_str: [*c]const u8 = @ptrCast(value.ptr);
    if (H5Awrite(attr, str_type, @ptrCast(&c_str)) < 0) return error.HDF5Error;
}

/// Write a scalar f64 attribute.
pub fn writeDoubleAttr(loc_id: hid_t, name: [:0]const u8, value: f64) Error!void {
    const space = H5Screate(H5S_SCALAR);
    if (space < 0) return error.HDF5Error;
    defer _ = H5Sclose(space);

    const attr = H5Acreate2(loc_id, name.ptr, H5T_NATIVE_DOUBLE_g, space, H5P_DEFAULT, H5P_DEFAULT);
    if (attr < 0) return error.HDF5Error;
    defer _ = H5Aclose(attr);

    if (H5Awrite(attr, H5T_NATIVE_DOUBLE_g, @ptrCast(&value)) < 0) return error.HDF5Error;
}
