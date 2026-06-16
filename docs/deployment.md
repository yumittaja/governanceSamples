# Käyttöönotto-opas

## Vaatimukset

- **Bicep CLI / Azure CLI** asennettuna.
- **Käyttöönoton taso:** hallintaryhmä (käytä sen tunnusta alla).
- **Oikeudet:** käyttöönottavalla periaatteella on oltava `Owner`, **tai** `Resource Policy Contributor` + `User Access Administrator`, hallintaryhmän tasolla — malli luo rooliosoituksen.
- **Hallittu identiteetti:** määritys käyttää järjestelmän osoittamaa identiteettiä, jolle on myönnetty sisäänrakennettu **Tag Contributor** -rooli (`4a9ae827-6dc8-4573-8ac7-8239d42aa03f`) hallintaryhmän tasolla, mitä `modify`-vaikutus edellyttää.

## Käyttöönotto

Kaksi käyttöönottoa ovat itsenäisiä ja kohdistuvat eri tasoihin. Parametrit on dokumentoitu erikseen kohdassa [Parametrit](parameters.md).

**1. Käytännöt (hallintaryhmä):**

```powershell
az deployment mg create `
  --management-group-id <your-mg-id> `
  --location swedencentral `
  --template-file policies.bicep `
  --parameters policies.bicepparam
```

**2. Työkirjat ja kustannusanalytiikka (tilaus):**

```powershell
az deployment sub create `
  --subscription <your-subscription-id> `
  --location swedencentral `
  --template-file resources.bicep `
  --parameters resources.bicepparam
```

> Ota kustannusputki käyttöön lisäämällä `deployCostManagement=true`. Vientien luonti ja Logic App -putki kuvataan kohdassa [Kustannustenhallinta ja FinOps](cost-management.md).

## Olemassa olevien resurssien korjaaminen (remediation)

Käytännöt `deny`/`modify` vaikuttavat vain **luonti-/päivityshetkellä**. Merkitäksesi jo olemassa olevat resurssit, suorita korjaustehtävä (remediation) kutakin periytyvää tunnistetta kohden käyttöönoton jälkeen (anna ensin muutaman minuutin ajan hallitun identiteetin rooliosoituksen levitä). `--definition-reference-id` on muotoa `inherit-<tagName>`:

```powershell
az policy remediation create `
  --name remediate-inherit-owner `
  --management-group <your-mg-id> `
  --policy-assignment tag-governance `
  --definition-reference-id inherit-owner
```
