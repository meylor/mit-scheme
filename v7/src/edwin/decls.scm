(fluid-let ((sf/default-syntax-table syntax-table/system-internal))
  (sf-conditionally
   '("bufinp"
     "bufott"
     "bufout"
     "comtab"
     "class"
     "clscon"
     "clsmac"
     "cterm"
     "entity"
     "grpops"
     "image"
     "macros"
     "make"
     "motion"
     "nvector"
     "paths"
     "regops"
     "rename"
     "rgxcmp"
     "ring"
     "screen"
     "search"
     "simple"
     "strpad"
     "strtab"
     "utils"
     "xform"
     "xterm"
     "winout"
     "winren")))

(fluid-let ((sf/default-syntax-table
	     (access edwin-syntax-table (->environment '(EDWIN)))))
  (sf-conditionally
   '("argred"
     "autold"
     "autosv"
     "basic"
     "bufcom"
     "buffer"
     "bufmnu"
     "bufset"
     "c-mode"
     "calias"
     "cinden"
     "comman"
     "comred"
     "curren"
     "debug"
     "debuge"
     "dired"     "editor"
     "edtstr"
     "evlcom"
     "filcom"
     "fileio"
     "fill"
     "hlpcom"
     "info"
     "input"
     "intmod"
     "iserch"
     "keymap"
     "kilcom"
     "kmacro"
     "lincom"
     "linden"
     "loadef"
     "lspcom"
     "midas"
     "modefs"
     "modes"
     "modlin"
     "motcom"
     "pasmod"
     "prompt"
     "reccom"
     "regcom"
     "regexp"
     "replaz"
     "schmod"
     "sercom"
     "struct"
     "syntax"
     "tags"
     "texcom"
     "things"
     "tparse"
     "tximod"
     "undo"
     "unix"
     "wincom"
     "xcom")))

(fluid-let ((sf/default-syntax-table
	     (access class-syntax-table (->environment '(EDWIN)))))
  (sf-conditionally
   '("window"
     "utlwin"
     "linwin"
     "bufwin"
     "bufwfs"
     "bufwiu"
     "bufwmc"
     "comwin"
     "modwin"
     "buffrm"
     "edtfrm"
     "winmis"
     "rescrn")))