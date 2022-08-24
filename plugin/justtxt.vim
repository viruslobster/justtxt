if exists("g:loaded_justtxt")
    finish
endif
let g:loaded_justtxt = 1

command! -nargs=0 JustTxtRun lua require("justtxt").run()
command! -nargs=0 JustTxtKill lua require("justtxt").kill(9)
command! -nargs=0 Test lua require("justtxt").test()
