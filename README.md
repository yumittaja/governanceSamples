# Azure-hallintaratkaisu: tunnisteet ja näkyvyys (Bicep)

Hallintaratkaisu esimerkki Azure-ympäristöön, jossa on **useita tilauksia** hallintaryhmän alla. Ratkaisu yhdistää kaksi toisiaan täydentävää osaa:

- **Kontrollit (Azure Policy)** — pakottavat ja korjaavat tunnisteet, jotta omistajuus, kustannuspaikat ja ympäristöt ovat aina merkittyinä.
- **Näkyvyys (Azure Monitor -työkirjat)** — visualisoivat hallinnan tilan, tietoturva-asennon ja kustannukset päätöksenteon tueksi.

Lisäksi ratkaisuun kuuluu **valinnainen kustannusdatan sisäänlukuputki** (Cost Management -vienti → Logic App → Log Analytics), joka tuottaa datan FinOps-työkirjalle.

## Mitä tämä tekee

### Kontrollit (Azure Policy)

| Käytäntö | Vaikutus | Toiminta |
|--------|--------|----------|
| `require-tag-on-resource-group` | `Deny` (määritettävissä) | Estää sellaisen resurssiryhmän luonnin tai päivityksen, josta puuttuu pakollinen tunniste (esim. `owner`). |
| `inherit-tag-from-resource-group` | `modify` | Kun resurssi luodaan tai päivitetään ja sen yläresurssiryhmällä on tunnisteelle ei-tyhjä arvo, resurssi saa saman tunnisteen/arvon. |
| `allowed-tag-values` | `Audit` (määritettävissä) | Merkitsee resurssit/resurssiryhmät, joiden tunnisteen arvo ei ole sallittujen listalla (vain kun tunniste on olemassa). |

Käytännöt on koottu yhteen **aloitteeseen** (`tag-governance-initiative`) ja määritetään kerran **hallintaryhmän** tasolla, joten säännöt koskevat automaattisesti kaikkia nykyisiä ja tulevia alatilauksia.

### Näkyvyys (Azure Monitor -työkirjat)

| Työkirja | Kategoria | Sisältö |
|----------|-----------|---------|
| **Azure Governance Workbook** | `governance` | Hallinnan tila: tunnisteiden kattavuus, omistajuus ja FinOps-attribuution valmius. Toimii kuukausittaisena hallinnan tuloskorttina. |
| **Azure Security Workbook** | `security` | Tietoturva-asento Azure Resource Graph -kyselyillä (ARG-turvalliset litteät kyselyt). |
| **Azure FinOps & Cost Management Workbook** | `finops` | Kustannusten kohdistus resurssiryhmittäin, palveluittain ja tunnisteittain. Kyselee `CostExport_CL`-taulua. *Valinnainen.* |

Hallinta- ja tietoturvatyökirjat otetaan aina käyttöön. FinOps-työkirja ja sen kustannusputki ovat valinnaisia (`deployCostManagement = true`).

## Dokumentaatio

| Opas | Sisältö |
|------|---------|
| [Arkkitehtuuri](docs/architecture.md) | Ratkaisun rakenne, kaavio, käytäntöjen toiminta ja tiedostoluettelo. |
| [Käyttöönotto-opas](docs/deployment.md) | Vaatimukset, käyttöönottokomennot ja olemassa olevien resurssien korjaaminen (remediation). |
| [Parametrit](docs/parameters.md) | Käyttöönottojen parametrit ja hallittujen tunnisteiden muoto. |
| [Kustannustenhallinta ja FinOps](docs/cost-management.md) | Kustannusviennin luonti, `CostExport_CL`-tietomalli ja Logic App -putki. |

## Pikakäyttöönotto

**1. Käytännöt (hallintaryhmä):**

```powershell
az deployment mg create `
  --management-group-id <your-mg-id> `
  --location swedencentral `
  --template-file policies.bicep `
  --parameters policies.bicepparam
```

**2. Työkirjat ja (valinnainen) kustannusanalytiikka (tilaus):**

```powershell
az deployment sub create `
  --subscription <your-subscription-id> `
  --location swedencentral `
  --template-file resources.bicep `
  --parameters resources.bicepparam
```

Kustannusputki ja FinOps-työkirja otetaan käyttöön lisäämällä `deployCostManagement=true`. Tarkemmat ohjeet ja oikeusvaatimukset löytyvät [käyttöönotto-oppaasta](docs/deployment.md).
