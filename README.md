<h1 align="center">
    <br/>
    Offline Ban list
</h1>

### [![GitHub license](https://img.shields.io/badge/license-GPLv3-blue.svg?style=flat-square)](https://github.com/Grey-rus/offlineban/blob/master/LICENSE)

### Ссылки
- [Скачать этот плагин](https://github.com/Grey-rus/offlineban/archive/master.zip)

### Описание
Позволяет банить игроков вышедших из игры, админам с флагом бана.
Меню автоматически прописывается в Управление игроками.

### Особенности
- Админы и боты в список не выводятся.
- После бана забаненый из списка пропадает.
- Игроки в списке не дублируются.
- Игрок вышедший из игры и снова вошедший из списка пропадает.
- Добавляется приписка в причине бана [Offline Ban]

### Установка
- В папке addons\sourcemod\configs настраиваем конфиг offban.cfg
- В папке addons\sourcemod\scripting есть файл offlineban_old.sp он для см ниже 1.7

### Команды
| Команда | Аргументы | Требуемый админ флаг | Что делает? |
|--------:|:---------:|:--------------------:|-------------|
|**sm\_offban\_clear**|-|**ADMFLAG\_ROOT**|Очистка истории|

### Цвета для чата
| Игра | Цвет | # |
|:----:|:----:|:-:|
|**Все**|Жёлтый|#1|
|**CS:GO**|RED|#2|
|**Все**|Светло-зелёный|#3|
|**Все**|Зелёный|#4|
|**CS:GO**|LIME|#5|
|**CS:GO**|LIGHTGREEN|#6|
|**CS:GO**|LIGHTRED|#7|
|**OrangeBox** (CS:S / TF2)|HTML-цвет (вместо **FFFFFF** - Ваш цвет в HEX-варианте)|#7FFFFFF|
|**CS:GO**|GRAY|#8|
|**CS:GO**|LIGHTOLIVE|#9|
|**CS:GO**|OLIVE|#10|
|**CS:GO**|PURPLE|#OB|
|**CS:GO**|LIGHTBLUE|#OC|
|**CS:GO**|BLUE|#OE|

### Сортировка в меню Администратора
- Дописываем в adminmenu_sorting.txt в нужное вам место в категории "PlayerCommands"
```
"item" "OfflineBans"
```