macroScript PKD_KitchenUnit
category:"Pro Kitchen Design"
tooltip:"Build Kitchen Units - PKD v12.5"
buttonText:"PKD Builder"
(
    on execute do
    (
        try ( destroyDialog PKD_MainUI ) catch ()
        fileIn @"d:\Social\Plugin\AI Agent\3ds Max Plugin\files\PKD_KitchenUnit_V125.ms"
    )
)
