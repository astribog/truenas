Скрипт создает снапшоты zvol, из них делает датасеты, затем из них создает iscsi экстенты, испоьзуя встроенную утилиту `midclt`. Скрипт работает только с TrueNAS Scale. Для коректной работы необходимо заранее вручную сконфигурировать iscsi targets и по желанию Initiator Group IDs. Запуск из под рута.
