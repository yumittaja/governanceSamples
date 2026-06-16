# Parametrit

## Käytäntöjen käyttöönotto (`policies.bicepparam`)

| Nimi | Oletus | Kuvaus |
|------|---------|-------------|
| `tags` | katso alta | Lista hallituista tunnisteista ja siitä, miten kutakin valvotaan. |
| `location` | `deployment().location` | Alue määrityksen hallitulle identiteetille. |
| `requireTagEffect` | `Deny` | require-tag-käytäntöjen vaikutus: `Deny`, `Audit` tai `Disabled`. |
| `allowedValuesEffect` | `Audit` | allowed-values-käytäntöjen vaikutus: `Audit`, `Deny` tai `Disabled`. |

## Resurssien käyttöönotto (`resources.bicepparam`)

| Nimi | Oletus | Kuvaus |
|------|---------|-------------|
| `location` | `deployment().location` | Alue hallintaresursseille. |
| `resourceGroupName` | `rg-governance` | Resurssiryhmä, joka isännöi työkirjoja ja kustannusanalytiikkaresursseja. |
| `deployCostManagement` | `false` | Ota käyttöön FinOps-työkirja ja sitä tukevat resurssit (tallennustili, Log Analytics -työtila, kustannusten sisäänluvun Logic App). |
| `costStorageAccountName` | generoitu | Globaalisti yksilöllinen tallennustili kustannusvienneille (3–24 pientä aakkosnumeerista merkkiä). |
| `costExportContainerName` | `cost-exports` | Blob-säiliö, joka vastaanottaa Cost Management -viennit. |
| `costWorkspaceName` | `log-cost-analytics` | Log Analytics -työtila, johon kustannusdata luetaan. |
| `costIngestionLogicAppName` | `logic-cost-ingestion` | Consumption Logic App, joka lukee viedyn kustannusdatan. |

## Hallittujen tunnisteiden muoto

Jokaisella `tags`-listan kohteella on muoto:

| Kenttä | Tyyppi | Kuvaus |
|-------|------|-------------|
| `name` | string | Tunnisteen nimi, esim. `owner`, `costcenter`. CAF suosittelee pienaakkosia avaimissa. |
| `mandateOnResourceGroup` | bool | Vaadi tunniste resurssiryhmissä. |
| `inheritToResources` | bool | Levitä resurssiryhmän tunnisteen arvo resursseihin. |
| `allowedValues` | string[] (valinnainen) | Kun asetettu, allowed-values-käytäntö validoi tunnisteen. |

Oletuksena hallitut tunnisteet (FinOps- ja hallinta-linjattu):

| Tunniste | Pakollinen RG:ssä | Periytyy | Sallitut arvot |
|-----|:---:|:---:|----------------|
| `owner` | ✔ | ✔ | — |
| `costcenter` | ✔ | ✔ | — |
| `environment` | ✔ | ✔ | `prod`, `staging`, `test`, `dev` |
| `businessunit` | — | ✔ | — |
| `application` | — | ✔ | — |
| `dataclassification` | — | — | `public`, `internal`, `confidential`, `restricted` |

Muokkaa `policies.bicepparam`-tiedostoa muuttaaksesi hallittuja tunnisteita ja vaikutuksia.
