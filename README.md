# Namelink zsh plugin

Namelink provides an automatically synchronized mapping of filesystem entries (typically symbolic links) in a set of directories to their counterparts in the named directory hash.

This facilitates a shared namespace between the `~foo` syntax inside zsh, and external processes such as an editor or file manager.

## ⚠️ WARNING ⚠️

Take care when linking across filesystems that may not always be accessible, such as network volumes, as it has the potential to slow down (or even hang) the shell if the hash needs rebuilding. The author recommends containing such links into a subdirectory beneath the scanned directory to prevent this occurring.

## Directory locations

The default behaviour is to house the entries in the single directory `~/.@`. You can customise this by invoking `namelink_setpath [directory ...]` and passing the set of directories to be scanned from now on.

## Examples

### Playing with /usr/local

```console
~% mkdir .@ && cd .@
~/.@% ln -s /usr/local ul
~/.@% echo ~ul
/usr/local
~/.@% ln -s ul/bin ulb
~/.@% cd ~ulb && pwd
/usr/local/bin
~ulb% rm ~/.@/ulb
~ul/bin% rm ~/.@/ul
/usr/local/bin% echo ~ul
zsh: no such user or named directory: ul
```

### Desktop GUI convenience

You may wish to use a parent directory with a human-readable name to enable easier navigation in a desktop context, however a short path lends itself to fewer keystrokes elsewhere. The author uses both:

```console
% cd
% ls -ld .@ Abbreviations
lrwxrwxr-x   1 jason  staff    13 25 Aug  2020 .@ -> Abbreviations
drwxrwxr-x  72 jason  staff  2304 20 Nov 10:17 Abbreviations
```

For example, on macOS, the abbreviated links can then become meaningfully available when opening a file:

![macOS open dialog](./media/macos-open-dialog.webp)
