if exists("b:current_syntax")
  finish
endif

syntax match SqlServerResultHeaderNoSpell /\%1l.*/ contains=@NoSpell

let b:current_syntax = "sqlserver-result"
