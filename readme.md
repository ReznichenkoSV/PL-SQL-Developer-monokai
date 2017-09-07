# PL/SQL Developer-monokai

Monokai color scheme for Pl/Sql Developer.

## Screenshots

![Monokai in Pl/Sql Developer](plsqldev_monokai.png?raw=true)

## Installation

### Install configuration files

Put `Profile\customtoolbars.ini` and `Profile\docking12.ini` files in your `%USERPROFILE%\AppData\Roaming\PLSQL Developer 12\` directory.

Put `Profile\Template\*` files in your `%USERPROFILE%\AppData\Roaming\PLSQL Developer 12\Template` directory.

Put `Profile\Preferences\Monokai.ini` and `Profile\Preferences\user.prefs` files in your `%USERPROFILE%\AppData\Roaming\PLSQL Developer 12\Preferences\%USERNAME%` directory.

After start activate Monokai theme

![Activate theme Monokai in Pl/Sql Developer](plsqldev_monokai_activate.png?raw=true)

### Install `AutoReplace.txt`

Put file `AutoReplace.txt` into your documents and specify the path in the settings `Preferences->Editor`.
Available autoreplace commands

    td_ = Custom\to_date.tpl
    tl_ = Custom\to_date long.tpl
    **_ = Custom\plsdqldoc comment.tpl
    88_ = Custom\plsdqldoc comment.tpl
    pl_ = Custom\dbms put_line.tpl
    echo = Custom\dbms put_line.tpl
    ex_ = Custom\exception block.tpl
    if_ = Custom\if block.tpl
    ie_ = Custom\if else block.tpl
    be_ = Custom\begin block.tpl
    se* = Custom\select.tpl
    se_ = Custom\select with rowid.tpl
    sed_ = Custom\select dual.tpl
    nf_ = Custom\no_format.tpl
    q_  = Custom\literal.tpl
    xp_ = Custom\xmltype_pretty_print.tpl
    xs_ = Custom\xmltype_xmlserialize.tpl
    xr_ = Custom\xmltype_xmlroot.tpl
    regl_ = Custom\regexp_like.tpl

### Install `Beautifier.br`

Put file `Beautifier.br` into your documents and specify the path in the settings `Preferences->PL/SQL Beautifier`.

### Install font Input

Download link [Font Input](http://input.fontbureau.com/)
