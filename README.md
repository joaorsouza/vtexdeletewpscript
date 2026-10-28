# vtexdeletewpscript

Script PowerShell para **apagar workspaces VTEX em lote** na conta em que você está logado no `vtex` CLI.

Por padrão ele roda em **dry-run**: só mostra o que seria apagado. Nada é removido sem o parâmetro `-Apply`.

## Pré-requisitos

- Windows com PowerShell 7+
- [VTEX CLI](https://developers.vtex.com/docs/guides/vtex-io-documentation-vtex-io-cli-install) instalado
- Login feito na conta desejada:
  ```powershell
  vtex login <conta>
  vtex whoami   # confirme a conta antes de apagar qualquer coisa
  ```

## Como funciona

1. Lê a lista atual com `vtex workspace list`.
2. Monta a lista de alvos conforme os parâmetros que você passou.
3. Remove da lista o que é protegido (veja [Proteções](#proteções)).
4. Mostra "Serão apagados" e "Ignorados".
5. Sem `-Apply`: para aqui (dry-run). Com `-Apply`: apaga em lotes com `vtex workspace delete -y`.
6. No fim mostra quantos foram apagados e quais falharam.

## Parâmetros

| Parâmetro | Tipo | O que faz |
|---|---|---|
| `-Pattern` | texto (regex) | Seleciona workspaces cujo nome casa com a regex |
| `-FromFile` | caminho | Seleciona os nomes listados no arquivo (um por linha) |
| `-Names` | lista de textos | Seleciona os nomes passados direto no comando |
| `-KeepFile` | caminho | **Modo inverso:** apaga tudo que NÃO estiver no arquivo |
| `-IncludeProduction` | switch | Permite apagar workspaces com `production=true` |
| `-Apply` | switch | Executa de verdade. Sem ele é dry-run |
| `-BatchSize` | número | Quantos workspaces por chamada de delete (padrão: 10) |

É obrigatório informar pelo menos um entre `-Pattern`, `-FromFile`, `-Names` e `-KeepFile`. Eles podem ser combinados; a união dos resultados é usada.

## Exemplos por caso

### 1. Apagar por padrão de nome (regex)

Dry-run primeiro:

```powershell
.\delete-workspaces.ps1 -Pattern '^(teste|tmp)\d*$'
```

Casa `teste`, `teste1`, `tmp22`, etc. Se a lista estiver certa, apague de verdade:

```powershell
.\delete-workspaces.ps1 -Pattern '^(teste|tmp)\d*$' -Apply
```

### 2. Apagar uma lista explícita em arquivo

Crie `apagar.txt` com um nome por linha. Linhas vazias e linhas começando com `#` são ignoradas:

```text
# workspaces de feature já mergeadas
feat100
fix200
spike300
```

```powershell
.\delete-workspaces.ps1 -FromFile .\apagar.txt          # dry-run
.\delete-workspaces.ps1 -FromFile .\apagar.txt -Apply   # apaga
```

### 3. Apagar poucos nomes direto no comando

```powershell
.\delete-workspaces.ps1 -Names feat100,fix200 -Apply
```

### 4. Modo inverso: apagar tudo, exceto uma lista

Crie `manter.txt` com os workspaces que devem sobreviver:

```text
feat100
fix200
```

```powershell
.\delete-workspaces.ps1 -KeepFile .\manter.txt          # dry-run: confira a lista com atenção
.\delete-workspaces.ps1 -KeepFile .\manter.txt -Apply   # apaga todo o resto
```

Se algum nome do `manter.txt` não existir na conta, o script avisa (não é erro).

### 5. Incluir workspaces de produção

Workspaces com `production=true` são ignorados por padrão. Para incluí-los:

```powershell
.\delete-workspaces.ps1 -Pattern '^release\d+$' -IncludeProduction -Apply
```

### 6. Ajustar o tamanho do lote

```powershell
.\delete-workspaces.ps1 -FromFile .\apagar.txt -BatchSize 5 -Apply
```

### 7. Guardar a saída em log

```powershell
.\delete-workspaces.ps1 -KeepFile .\manter.txt          *> dryrun.log
.\delete-workspaces.ps1 -KeepFile .\manter.txt -Apply   *> apply.log
```

### 8. Combinar critérios

```powershell
.\delete-workspaces.ps1 -Pattern '^tmp\d*$' -Names extra1,extra2 -Apply
```

## Proteções

O script nunca apaga, mesmo que o nome esteja na seleção:

| Caso | Mensagem em "Ignorados" |
|---|---|
| `master` | `(protegido)` |
| O workspace em uso agora (marcado com `*` no `vtex workspace list`) | `(workspace atual, troque antes)` |
| Nome que não existe na conta | `(não existe)` |
| Workspace com `production=true` (sem `-IncludeProduction`) | `(production=true; use -IncludeProduction)` |

Para liberar o workspace atual, troque antes: `vtex use master`.

## Fluxo recomendado

```powershell
vtex whoami                                        # 1. confirme a conta
vtex workspace list                                # 2. veja o que existe
.\delete-workspaces.ps1 -KeepFile .\manter.txt     # 3. dry-run e revisão da lista
.\delete-workspaces.ps1 -KeepFile .\manter.txt -Apply   # 4. execução
```

> **Atenção:** apagar workspace é irreversível. Sempre revise a saída do dry-run antes de usar `-Apply`.

## Arquivos do projeto

| Arquivo | Versionado | Descrição |
|---|---|---|
| `delete-workspaces.ps1` | sim | O script |
| `README.md` | sim | Esta documentação |
| `.gitignore` | sim | Ignora `*.txt` e `*.log` para não publicar nomes reais de workspaces |
| `apagar.txt` | não | Lista de nomes a apagar, usada com `-FromFile` |
| `manter.txt` | não | Lista de nomes a preservar, usada com `-KeepFile` |
| `all.txt` | não | Snapshot opcional de todos os workspaces antes da limpeza |
| `after.txt` | não | Snapshot opcional do que sobrou depois da limpeza |
| `dryrun.log` | não | Saída de um dry-run guardada para conferência |
| `apply.log` | não | Saída da execução real guardada como registro |

Os arquivos `.txt` e `.log` são gerados por você durante o uso e ficam só na sua máquina.

## Solução de problemas

- **"Não consegui ler a lista de workspaces"**: você não está logado, ou o formato de saída do `vtex workspace list` mudou. Rode `vtex login` e tente de novo.
- **"Nenhum critério informado"**: passe ao menos um de `-Pattern`, `-FromFile`, `-Names` ou `-KeepFile`.
- **Um lote falhou**: o script marca todos os nomes daquele lote como falha, mesmo que parte tenha sido apagada. Rode `vtex workspace list` e repita só para o que sobrou.
