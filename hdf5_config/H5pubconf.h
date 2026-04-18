/* Cross-platform H5pubconf.h for SIEtoHDF5 project.
 *
 * Targets: linux-x86_64, linux-aarch64, windows-x86_64,
 *          macos-x86_64, macos-aarch64
 *
 * All targets are 64-bit, little-endian.
 *
 * Disabled features: MPI/parallel, threading/threadsafe,
 *   zlib/deflate, szip, ROS3, HDFS, mirror VFD, direct VFD,
 *   subfiling VFD, MAP API, Fortran, C++, Java.
 */

#ifndef H5pubconf_H
#define H5pubconf_H

/* ------------------------------------------------------------------ */
/*  Platform detection                                                 */
/* ------------------------------------------------------------------ */

#if defined(_WIN32)
  #define H5_HAVE_WINDOWS     1
  #define H5_HAVE_WIN32_API   1
  #define H5_HAVE_MINGW       1
  #define H5_HAVE_WINDOW_PATH 1
#endif

#if defined(__APPLE__)
  #define H5_HAVE_DARWIN 1
#endif

/* Static library build — disables dllimport/dllexport on Windows */
#define H5_BUILT_AS_STATIC_LIB 1

/* ------------------------------------------------------------------ */
/*  Type sizes — common to all 64-bit targets                          */
/* ------------------------------------------------------------------ */

#define H5_SIZEOF_BOOL    1
#define H5_SIZEOF_CHAR    1
#define H5_SIZEOF_SHORT   2
#define H5_SIZEOF_INT     4
#define H5_SIZEOF_UNSIGNED 4
#define H5_SIZEOF_FLOAT   4
#define H5_SIZEOF_DOUBLE  8
#define H5_SIZEOF_LONG_LONG 8

#define H5_SIZEOF_INT8_T   1
#define H5_SIZEOF_UINT8_T  1
#define H5_SIZEOF_INT16_T  2
#define H5_SIZEOF_UINT16_T 2
#define H5_SIZEOF_INT32_T  4
#define H5_SIZEOF_UINT32_T 4
#define H5_SIZEOF_INT64_T  8
#define H5_SIZEOF_UINT64_T 8

#define H5_SIZEOF_INT_LEAST8_T   1
#define H5_SIZEOF_UINT_LEAST8_T  1
#define H5_SIZEOF_INT_LEAST16_T  2
#define H5_SIZEOF_UINT_LEAST16_T 2
#define H5_SIZEOF_INT_LEAST32_T  4
#define H5_SIZEOF_UINT_LEAST32_T 4
#define H5_SIZEOF_INT_LEAST64_T  8
#define H5_SIZEOF_UINT_LEAST64_T 8

#define H5_SIZEOF_TIME_T    8
#define H5_SIZEOF_PTRDIFF_T 8

/* _Float16 not available on our targets */
#define H5_SIZEOF__FLOAT16 0

/* ------------------------------------------------------------------ */
/*  Platform-specific type sizes                                       */
/* ------------------------------------------------------------------ */

#if defined(_WIN32)
  /* Windows LLP64 */
  #define H5_SIZEOF_LONG   4
  #define H5_SIZEOF_SIZE_T 8
  #define H5_SIZEOF_SSIZE_T 8
  #define H5_SIZEOF_OFF_T  4
  #define H5_SIZEOF_LONG_DOUBLE 8
  #define H5_SIZEOF_INT_FAST8_T   1
  #define H5_SIZEOF_UINT_FAST8_T  1
  #define H5_SIZEOF_INT_FAST16_T  4
  #define H5_SIZEOF_UINT_FAST16_T 4
  #define H5_SIZEOF_INT_FAST32_T  4
  #define H5_SIZEOF_UINT_FAST32_T 4
  #define H5_SIZEOF_INT_FAST64_T  8
  #define H5_SIZEOF_UINT_FAST64_T 8

#elif defined(__APPLE__)
  /* macOS — universal binary compatible (following upstream pattern) */
  #if defined(__LP64__) && __LP64__
    #define H5_SIZEOF_LONG    8
    #define H5_SIZEOF_SIZE_T  8
    #define H5_SIZEOF_SSIZE_T 8
  #else
    #define H5_SIZEOF_LONG    4
    #define H5_SIZEOF_SIZE_T  4
    #define H5_SIZEOF_SSIZE_T 4
  #endif
  #define H5_SIZEOF_OFF_T 8
  #if defined(__x86_64__)
    #define H5_SIZEOF_LONG_DOUBLE 16
  #elif defined(__aarch64__)
    #define H5_SIZEOF_LONG_DOUBLE 8
  #endif
  #define H5_SIZEOF_INT_FAST8_T   1
  #define H5_SIZEOF_UINT_FAST8_T  1
  #define H5_SIZEOF_INT_FAST16_T  8
  #define H5_SIZEOF_UINT_FAST16_T 8
  #define H5_SIZEOF_INT_FAST32_T  8
  #define H5_SIZEOF_UINT_FAST32_T 8
  #define H5_SIZEOF_INT_FAST64_T  8
  #define H5_SIZEOF_UINT_FAST64_T 8

#else
  /* Linux LP64 */
  #define H5_SIZEOF_LONG    8
  #define H5_SIZEOF_SIZE_T  8
  #define H5_SIZEOF_SSIZE_T 8
  #define H5_SIZEOF_OFF_T   8
  #if defined(__x86_64__)
    #define H5_SIZEOF_LONG_DOUBLE 16
  #elif defined(__aarch64__)
    #define H5_SIZEOF_LONG_DOUBLE 16
  #endif
  #define H5_SIZEOF_INT_FAST8_T   1
  #define H5_SIZEOF_UINT_FAST8_T  1
  #define H5_SIZEOF_INT_FAST16_T  8
  #define H5_SIZEOF_UINT_FAST16_T 8
  #define H5_SIZEOF_INT_FAST32_T  8
  #define H5_SIZEOF_UINT_FAST32_T 8
  #define H5_SIZEOF_INT_FAST64_T  8
  #define H5_SIZEOF_UINT_FAST64_T 8
#endif

/* Complex number type sizes */
#if !defined(_WIN32)
  #define H5_SIZEOF_FLOAT_COMPLEX  8
  #define H5_SIZEOF_DOUBLE_COMPLEX 16
  #if defined(__x86_64__)
    #define H5_SIZEOF_LONG_DOUBLE_COMPLEX 32
  #elif defined(__aarch64__) && defined(__APPLE__)
    #define H5_SIZEOF_LONG_DOUBLE_COMPLEX 16
  #elif defined(__aarch64__)
    #define H5_SIZEOF_LONG_DOUBLE_COMPLEX 32
  #endif
#endif

/* ------------------------------------------------------------------ */
/*  Available headers                                                  */
/* ------------------------------------------------------------------ */

/* POSIX-only headers */
#if !defined(_WIN32)
  #define H5_HAVE_SYS_TIME_H     1
  #define H5_HAVE_SYS_FILE_H     1
  #define H5_HAVE_SYS_IOCTL_H    1
  #define H5_HAVE_SYS_RESOURCE_H 1
  #define H5_HAVE_SYS_SOCKET_H   1
  #define H5_HAVE_DLFCN_H        1
  #define H5_HAVE_PWD_H          1
  #define H5_HAVE_PTHREAD_H      1
  #define H5_HAVE_ARPA_INET_H    1
  #define H5_HAVE_NETDB_H        1
  #define H5_HAVE_NETINET_IN_H   1
#endif

/* Available on all targets (mingw provides unistd.h) */
#define H5_HAVE_UNISTD_H       1

/* Available on all targets including mingw */
#define H5_HAVE_SYS_STAT_H     1
#define H5_HAVE_DIRENT_H       1
#define H5_HAVE_STDATOMIC_H    1

/* ------------------------------------------------------------------ */
/*  Available functions                                                */
/* ------------------------------------------------------------------ */

#if !defined(_WIN32)
  #define H5_HAVE_ALARM          1
  #define H5_HAVE_ASPRINTF       1
  #define H5_HAVE_CLOCK_GETTIME  1
  #define H5_HAVE_FCNTL          1
  #define H5_HAVE_FLOCK          1
  #define H5_HAVE_FORK           1
  #define H5_HAVE_FSEEKO         1
  #define H5_HAVE_GETHOSTNAME    1
  #define H5_HAVE_GETRUSAGE      1
  #define H5_HAVE_GETTIMEOFDAY   1
  #define H5_HAVE_IOCTL          1
  #define H5_HAVE_PREADWRITE     1
  #define H5_HAVE_STRDUP         1
  #define H5_HAVE_STRCASESTR     1
  #define H5_HAVE_SYMLINK        1
  #define H5_HAVE_TMPFILE        1
  #define H5_HAVE_VASPRINTF      1
  #define H5_HAVE_WAITPID        1
#endif

#if defined(_WIN32)
  /* mingw provides strdup, tmpfile, gethostname */
  #define H5_HAVE_STRDUP  1
  #define H5_HAVE_TMPFILE 1
  #define H5_HAVE_GETHOSTNAME 1
  #define H5_HAVE_FSEEKO  1
#endif

/* ------------------------------------------------------------------ */
/*  Available libraries                                                */
/* ------------------------------------------------------------------ */

#if !defined(_WIN32)
  #define H5_HAVE_LIBDL 1
  #define H5_HAVE_LIBM  1
#endif

/* ------------------------------------------------------------------ */
/*  OS-specific features                                               */
/* ------------------------------------------------------------------ */

#if !defined(_WIN32)
  #define H5_HAVE_STAT_ST_BLOCKS 1
  #define H5_HAVE_TM_GMTOFF      1
  #define H5_HAVE_TIMEZONE        1
  #define H5_HAVE_TIOCGETD        1
  #define H5_HAVE_TIOCGWINSZ      1
#endif

/* ------------------------------------------------------------------ */
/*  Compiler features                                                  */
/* ------------------------------------------------------------------ */

#if !defined(_MSC_VER)
  #define H5_HAVE_ATTRIBUTE 1
#endif

#if !defined(_WIN32)
  #define H5_HAVE_C99_COMPLEX_NUMBERS 1
  #define H5_HAVE_COMPLEX_NUMBERS     1
#endif

/* Reentrant qsort */
#define H5_HAVE_QSORT_REENTRANT 1

/* ------------------------------------------------------------------ */
/*  Disabled features                                                  */
/* ------------------------------------------------------------------ */

/* No MPI / parallel */
/* #undef H5_HAVE_PARALLEL */

/* No threading */
/* #undef H5_HAVE_THREADS */
/* #undef H5_HAVE_THREADSAFE */
/* #undef H5_HAVE_CONCURRENCY */
/* #undef H5_HAVE_C11_THREADS */

/* No compression filters */
/* #undef H5_HAVE_FILTER_DEFLATE */
/* #undef H5_HAVE_FILTER_SZIP */
/* #undef H5_HAVE_ZLIB_H */
/* #undef H5_HAVE_SZLIB_H */
/* #undef H5_HAVE_LIBZ */
/* #undef H5_HAVE_LIBSZ */

/* No optional VFDs */
/* #undef H5_HAVE_ROS3_VFD */
/* #undef H5_HAVE_MIRROR_VFD */
/* #undef H5_HAVE_DIRECT */
/* #undef H5_HAVE_SUBFILING_VFD */
/* #undef H5_HAVE_IOC_VFD */
/* #undef H5_HAVE_LIBHDFS */
/* #undef H5_HAVE_HDFS_H */

/* No MAP API */
/* #undef H5_HAVE_MAP_API */

/* ------------------------------------------------------------------ */
/*  Endianness                                                         */
/* ------------------------------------------------------------------ */

/* All our targets are little-endian */
#if defined(__APPLE__)
  #if defined(__BIG_ENDIAN__)
    #define WORDS_BIGENDIAN 1
  #endif
#endif
/* Linux and Windows: x86_64/aarch64 are little-endian */
/* #undef WORDS_BIGENDIAN */

/* ------------------------------------------------------------------ */
/*  File locking                                                       */
/* ------------------------------------------------------------------ */

#define H5_USE_FILE_LOCKING 1
#define H5_IGNORE_DISABLED_FILE_LOCKS 1

/* ------------------------------------------------------------------ */
/*  Data conversion                                                    */
/* ------------------------------------------------------------------ */

#define H5_WANT_DATA_ACCURACY    1
#define H5_WANT_DCONV_EXCEPTION  1
#define H5_LDOUBLE_TO_LLONG_ACCURATE 1
#define H5_LLONG_TO_LDOUBLE_CORRECT  1

/* ------------------------------------------------------------------ */
/*  File offsets                                                       */
/* ------------------------------------------------------------------ */

#if !defined(_WIN32)
  #define H5__FILE_OFFSET_BITS 64
#endif

/* ------------------------------------------------------------------ */
/*  API version                                                        */
/* ------------------------------------------------------------------ */

#define H5_USE_200_API_DEFAULT 1

/* ------------------------------------------------------------------ */
/*  Library info                                                       */
/* ------------------------------------------------------------------ */

#define H5_HAVE_EMBEDDED_LIBINFO 1

/* ------------------------------------------------------------------ */
/*  C precision                                                        */
/* ------------------------------------------------------------------ */

#define H5_PAC_C_MAX_REAL_PRECISION 33

/* ------------------------------------------------------------------ */
/*  Package info                                                       */
/* ------------------------------------------------------------------ */

#define H5_PACKAGE          "hdf5"
#define H5_PACKAGE_BUGREPORT "help@hdfgroup.org"
#define H5_PACKAGE_NAME     "HDF5"
#define H5_PACKAGE_STRING   "HDF5 2.1.1"
#define H5_PACKAGE_TARNAME  "hdf5"
#define H5_PACKAGE_URL      ""
#define H5_PACKAGE_VERSION  "2.1.1"
#define H5_VERSION          "2.1.1"

/* ------------------------------------------------------------------ */
/*  Plugin path                                                        */
/* ------------------------------------------------------------------ */

#define H5_DEFAULT_PLUGINDIR "/usr/local/hdf5/lib/plugin"

#endif /* H5pubconf_H */
