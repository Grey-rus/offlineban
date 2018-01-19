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
- В папке addons\sourcemod\configs\sourcebans добавить в конфиг sourcebans.cfg
```
"BanTime"
{
    "0"          "Навсегда"
    "5"          "На 5 мин."
    "30"         "На 30 мин."
    "60"         "На 1 час"
    "1440"       "На 1 день"
    "10080"      "На неделю"
    "43200"      "На месяц"
    "129600"     "На 3 месяця"
}
```
Если у вес не стоит sourcebans, то не нужно ни чего добавлять, конфиг offban.cfg

### Команды
| Команда | Аргументы | Требуемый админ флаг | Что делает? |
|--------:|:---------:|:--------------------:|-------------|
|**sm\_offban\_clear**|-|**ADMFLAG\_ROOT**|Очистка истории|

### Квары
| Квар | Описание |
|--------:|:--------------------|
|**sm\_offban\_timeformat**|Формат времени|
|**sm\_offban\_max\_stored**|Максимальное количество игроков в меню|
|**sm\_offban\_map\_clear**|Очистка истории после смены карты|
|**sm\_offban\_del\_con\_players**|Удалять ли из истории вновь подключившихся игроков|
|**sm\_offban\_menu\_nast**|Как показывать мены выбора игроков 1. name,time 2. name,steam 3. name,steam,time|
|**sm\_offban\_menu\_newline**|Перенос строк в меню|
|**sm\_offban\_steam\_typ**|Тип стим айди 1. старый 2. новый 3. комьюнити ид|

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