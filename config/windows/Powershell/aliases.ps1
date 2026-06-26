# Aliases — Windows parity with config/unix/.zshrc.base.
# Dot-sourced from the PowerShell profile. Kept in its own file so it can be
# tested in isolation (no starship/fnm/zoxide init to fail under the test host).

# PowerShell resolves aliases BEFORE functions, so the built-in aliases
# gc/gp/gl/gm/gcm would shadow the git functions below. Drop them first.
Remove-Item Alias:gc, Alias:gp, Alias:gl, Alias:gm, Alias:gcm -Force -ErrorAction SilentlyContinue

# vim is no longer installed (neovim is the editor); keep muscle memory.
Set-Alias vim nvim

# ls aliases. Get-ChildItem is already long-format; -Force shows hidden entries.
function l    { Get-ChildItem -Force @args }
function la   { Get-ChildItem -Force @args }
function ll   { Get-ChildItem @args }
function lsa  { Get-ChildItem -Force @args }

# git aliases — same subset as .zshrc.base.
Set-Alias g git
function ga     { git add @args }
function gaa    { git add --all @args }
function gst    { git status @args }
function gss    { git status --short @args }
function gc     { git commit --verbose @args }
function gca    { git commit --verbose --all @args }
function gco    { git checkout @args }
function gcb    { git checkout -b @args }
# gcm — checkout the main branch (zsh git_main_branch, inlined).
function gcm {
    foreach ($b in 'main', 'master', 'trunk') {
        git show-ref --quiet --verify "refs/heads/$b"
        if ($LASTEXITCODE -eq 0) { git checkout $b; return }
    }
}
function gb     { git branch @args }
function gba    { git branch --all @args }
function gbd    { git branch --delete @args }
function gd     { git diff @args }
function gds    { git diff --staged @args }
function gf     { git fetch @args }
function gl     { git pull @args }
function gp     { git push @args }
function gpsup  { git push --set-upstream origin HEAD @args }
function gm     { git merge @args }
function grb    { git rebase @args }
function grh    { git reset @args }
function glo    { git log --oneline --decorate @args }
function glog   { git log --oneline --decorate --graph @args }
function gloga  { git log --oneline --decorate --graph --all @args }
function glol   { git log --graph --pretty="%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%ar) %C(bold blue)<%an>%Creset" @args }
function glola  { git log --graph --pretty="%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%ar) %C(bold blue)<%an>%Creset" --all @args }
function gcl    { git clone --recurse-submodules @args }
function gsta   { git stash @args }
function gstp   { git stash pop @args }
