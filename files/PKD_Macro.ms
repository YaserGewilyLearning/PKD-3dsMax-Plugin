macroScript PKD_KitchenUnit
category:"Pro Kitchen Design"
tooltip:"Build Kitchen Units - PKD v14.0 Modular"
buttonText:"PKD Builder 14"
(
    on execute do
    (
        try ( destroyDialog PKD_MainUI ) catch ()
        fileIn @"d:\Social\Plugin\AI Agent\3ds Max Plugin\files\PKD_KitchenUnit_V14.0_Modular.ms"
    )
)
