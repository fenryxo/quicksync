export DIORITE_LOG_IPC_SERVER="yes"
export DIORITE_LOG_MESSAGE_SERVER="yes"

prompt_prefix='\[\033[1;33m\]QuickSync\[\033[00m\]'
[[ "$PS1" = "$prompt_prefix"* ]] || export PS1="$prompt_prefix $PS1"
unset prompt_prefix

rebuild()
{
    ./waf distclean configure build "$@"
}

run()
{
    program="$1"
    shift
    ./waf -v && build/$program -D "$@"

}
