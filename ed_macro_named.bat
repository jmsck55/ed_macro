@echo off
REM Copyright (c) 2020 James Cook
IF NOT "%EUDIR%"=="" GOTO label
set EUDIR=%ONEDRIVE%\euphoria40
set path=%EUDIR%\bin;%path%
:label
eui -D USE_CONTROL_KEYS ed_macro_named.ex %*
