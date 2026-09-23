# Blood polish — fechamento, 23/09/2026

Implementação incremental concluída; **P0 de encerramento nativo permanece pendente, sem causa identificada**. O parse, o headless básico final e uma única execução Compatibility básica terminaram normalmente. Isso não apaga o crash registrado antes neste mesmo passe. Não há aprovação visual, sonora ou garantia de estabilidade prolongada.

## As oito reclamações

| Reclamação | Causa encontrada | Implementação / antes → depois | Custo de performance e memória | Limitação restante |
|---|---|---|---|---|
| 1. Daggers pareciam spray genérico | O fan físico já usava o plano do swing, mas a resposta genérica de impacto sobrescrevia a escolha de stain; o stretch do pattern não se traduzia em leitura líquida específica. | Fan, velocidades e cast-off existentes preservados. SLASHING recebe wake mais pronunciado e mantém STREAK na deposição com tangente válida, com aspecto mínimo de 1,65. Antes o override apagava essa identidade; agora o footprint conserva o corte. | Mesmos droplets, cinco camadas e meshes. Sem ribbon, emitter ou trail nodes adicionais. | A captura mostra leque e pequenos streaks; a força da identidade em primeira pessoa ainda depende do jogador. Não foi criado um arco geométrico separado. |
| 2. Stains desapareciam abruptamente | Eviction devolvia o slot imediatamente; o vencimento de stains também podia parar quando o process de partículas era desligado. | `ACTIVE → FADING → FREE`, alpha em custom data, varredura no passo físico. Reserva proativa de slots; material recém-criado não é elegível por cinco segundos. | Até 128 fades, 64 slots examinados/passo; 14.336 bytes brutos de novos arrays no preset atual, sem incluir overhead. Nenhum material por stain. | Saturação total pode reter massa de novos contatos enquanto os antigos terminam de desaparecer. Geometria invalidada continua removendo imediatamente uma marca sem suporte. |
| 3. Círculos perfeitos | Máscaras pequenas de atlas permaneciam muito regulares, especialmente em impacto normal. | UV warp limitado dentro do quad e taper direcional; grandes máscaras mantêm breakup procedural. O contato normal fica aproximadamente redondo, com borda deformada. | Duas funções seno e aritmética no shader; sem novas texturas ou instâncias. | Não há medição de GPU. A amplitude artística precisa do playtest; não é simulação de borda líquida. |
| 4. Chuva de sangue inaudível | O acumulador existia e recebia colisões. Fonte de baixa amplitude, base −30 dB e unit size de 2 m produziam atenuação acumulada muito forte em comparação ao combate. | Placeholder normalizado para pico 0,7; base −21 dB, teto −16 dB e unit size 5 m. Mantidos agrupamento de 80 ms, células de 1,2 m, textura densa e variação de superfície. Expiração de clusters em 0,35 s impede áudio atrasado. O mixer nativo recebeu sinal nos três casos testados. | Mesmas seis vozes e oito WAV gerados no setup. Normalização só na construção. Até 32 clusters e dois novos eventos/frame. | Mixer não prova aprovação auditiva. Assets continuam provisórios; combate deve permanecer dominante no playtest. Metal compartilha resposta hard/smooth, não possui banco exclusivo. |
| 5. Movimento aéreo pouco legível | A apresentação arredondada tinha deformação limitada, mas nenhuma cauda visual específica. | O shader alonga e afina somente os vértices traseiros de gotas elegíveis, alinhados à velocidade. Sem wake abaixo de 5 m/s; cauda adicional limitada a 18 cm. | Até 96 slots existentes da camada medium; zero novos nodes, buffers, materiais ou draws. | É uma cauda instantânea, não histórico espacial de posições. Termina na colisão. A seleção por slots é fixa e barata; não é ordenação completa por distância. |
| 6. Stains perdiam direção | Além do override de família, trocar uma máscara alongada do atlas por uma procedural preservava a compensação assimétrica de padding do bitmap, anulando parte do aspecto. | Máscara procedural usa sua própria ocupação simétrica, mantendo aspecto de incidência, eixo longo na velocidade projetada e taper downstream. A série 90°–15° agora apresenta aspecto crescente. | Correção de dimensões e custom data por stain, sem queries adicionais. | Quad suportado continua sendo aproximação planar. O fixture angular controlado é de chão; paredes usam o mesmo cálculo mas a inspeção angular completa em parede fica para o manual. |
| 7. Grão pequeno virava poça enorme | O flag catastrófico do evento podia liberar um cap grande para qualquer classe de gota; um único parcel estatístico desbloqueava muito crescimento. | Cap catastrófico exige classe LARGE ou maior. `target`, `rendered` e crédito de área são separados: cada depósito financia no máximo 0,08 m² de expansão, dentro da massa e janela existentes. Antes um flag do evento bastava; agora o tamanho direto e a expansão têm limites distintos. | Um escalar por pool, até 1.024 patches, usando a mesma camada e validação de suporte. | Crédito limitado pode deixar a área apresentada abaixo do alvo de massa. Há acomodação de até 0,3 s após a entrada, não crescimento ilimitado sem fonte. |
| 8. Sobrevivente de explosão deixava de sangrar | Esgotamento do estoque vivo: `.13 × 2.6 × 2.4 × (1 + 1.4 × .8) = 1.719744` reservatórios solicitados por um HIGH_ENERGY não letal de cabeça com energia 2,4. O próximo hit calculava sua fração sobre zero. | Saque não letal limitado a 65% do sangue restante, para todas as famílias. Sem reposição fictícia. Testado o caminho Weapon → hurtbox → dano → reservoir → release → admissão → representantes → stain do próprio evento. | Um `minf` por saque, nenhum estado ou recurso novo por vítima. | Reservatório realmente esgotado por perdas posteriores ainda pode sangrar pouco ou nada. O limite é uma decisão estilizada de continuidade de sangue, não alteração de dano/vida. |

## Estado persistente e escopo

Não foi encontrado `victim_seen`, `already_bled` ou deduplicador de vida inteira causando o bug do sobrevivente. A identidade transitória dos hits permaneceu independente. O **estado persistente incorretamente zerado era `remaining_blood`**, por um saque não letal sem teto adequado. A correção não inventa um reset de flags inexistentes.

As sequências finais confirmadas foram HIGH_ENERGY → BALLISTIC, HIGH_ENERGY → SLASHING e BLUNT → BALLISTIC, com espera de frames entre ataques, vítima viva, dano aceito, família correta, massa positiva, representante do novo event ID e deposição desse mesmo evento. As massas do segundo hit na execução nativa foram aproximadamente 0,04438, 0,052325 e 0,04438 unidades normalizadas.

Paleta `#DC143C`, física de voo/drag, separação entre diâmetro e massa representada, reservatório, tecido, runoff, cast-off, fan no plano real do swing e geometria por vítima foram preservados. Não houve nova pesquisa nem redesenho. Recursos de paleta/perfis/física, arquivos de armas, dano/timings, movimento/bhop/slide/dash, selector, player/FOV e câmera são idênticos ao snapshot do início do polish. Comparação: [scope_manifest.json](validation/blood_polish/scope_manifest.json). Alterações anteriores no workspace foram preservadas; `git diff HEAD` inclui trabalho prévio e não é a lista deste passe. Nenhum commit foi feito.

## Fade, crescimento e limites

Fade escreve apenas `INSTANCE_CUSTOM.z`; o shader o multiplica na opacidade. A geometria e o material permanecem alocados. Classes menores usam 0,25 s, médias 0,65 s e áreas grandes 1,2 s. A classificação usa o footprint, sem criar objetos por classe. Stains antigas começam a sair antes de acabar a reserva livre. Pools recebendo expansão renovam a idade de apresentação. Pools já em fade não são ressuscitados por uma atualização atrasada.

O teste de pressão aciona o mesmo caminho de retirement sem precisar construir milhares de marcas. Registrou alpha **1 → 0,875 → 0,750 → 0,625**, seguido de slot livre somente ao terminar. A invalidação geométrica tem precedência sobre o fade, para não manter sangue pairando.

Pools preservam os limites anteriores de massa, suporte, área máxima e janela de acomodação. A nova coluna `credit` limita quanto cada entrada pode expandir. A sequência controlada de quatro depósitos atingiu **0,08 → 0,16 → 0,24 → 0,32 m² nominais**. Depois de cessar a entrada e terminar a janela, a área parou. Esses números não são cobertura única visível nem área forense.

| Estado/recurso | Capacidade explícita | Alocação |
|---|---:|---|
| Fades simultâneos | 128 | Três PackedArrays no setup |
| Idade das stains | 3.200 | Um float por slot existente |
| Varredura para fade | 64 slots/passo | Cursor escalar |
| Trails | 96 slots medium, dentro dos 520 existentes | Sem nova lista ou instância |
| Áudio | 6 players / 2 novos eventos por frame | Setup único, reuso |
| Clusters de áudio | 32 / idade máxima 0,35 s | Dicionário limitado |
| Histórico diagnóstico de áudio | 32 entradas | Limitado pelo acumulador |
| Wet patches / pools | Até 1.024 cada; pools subordinados aos patches | Limite anterior preservado |
| Surface MultiMesh | 3.200 slots | Capacidade fixa |
| Queries / novas stains | 640 / 48 por frame | Limites anteriores preservados |

Os fades acrescentam até 128 atualizações escalares por passo, distintas das 48 criações/reescritas geométricas. Continuam no mesmo commit de camada. Fade pode manter a camada dirty durante cleanup; não se afirma custo zero de upload. Não foram criados Mesh, Material, MultiMesh ou RID em caminhos quentes pelo polish. O índice de massa/base da célula é apagado quando sua última stain sai, evitando crescimento histórico desse índice durante reciclagem.

## Parâmetros novos e ajustados

Em `BloodStabilitySettings`, carregado pelo recurso existente `data/blood/blood_stability.tres`:

| Parâmetro | Valor |
|---|---:|
| `max_fading_stains` | 128 |
| `fade_reserve_slots` | 96 |
| `fade_scan_per_step` | 64 |
| `fade_min_age_s` | 5,0 |
| `fade_micro_s` / `fade_medium_s` / `fade_pool_s` | 0,25 / 0,65 / 1,2 |
| `max_trails` | 96 |
| `trail_min_speed` | 5 m/s |
| `trail_max_length_m` | 0,18 |
| `trail_time_s` | 0,012 |
| `slash_trail_gain` | 1,65 |
| `slash_stain_aspect` | 1,65 |
| `directional_tail_strength` | 0,35 |
| `pool_area_credit_per_deposit` | 0,08 m² |
| `audio_unit_size_m` | 5 |
| `audio_cluster_max_age_s` | 0,35 |
| `audio_base_db` / `audio_max_db` — ajustados | −21 / −16 |

Em `ReservoirConfig`: `max_nonlethal_fraction = 0.65`. Nenhum parâmetro de arma ou movimento foi alterado. Os `.tres` existentes usam esses novos defaults sem precisar ser regravados.

## Áudio: evidência e limites

O WAV antigo de gota tinha pico aproximado 0,434 e RMS 0,0613 antes de ganho e distância. O novo sintetizador normaliza o pico para 0,7 no setup. A unidade de distância aumenta de 2 para 5 m e o ganho base sobe 9 dB. Isso corrige fatores concretos de inaudibilidade, sem afirmar que o balanceamento final foi ouvido/aprovado pelo jogador.

O fixture Compatibility conecta as seis vozes a um único bus de captura criado no startup do teste, com buffer de 0,5 s. Produção continua com players 3D e agrupamento existente. Resultado real do mixer:

| Impactos próximos | Vozes novas | Ganho do evento | RMS capturado |
|---:|---:|---:|---:|
| 1 | 1 | −20,809 dB | 0,003399 |
| 10 | 1 | −19,614 dB | 0,014226 |
| 100 | 1 | −16,204 dB | 0,025419 |

RMS não é loudness percebido, e esta captura não inclui comparação simultânea com combate. A superfície altera o stream/filtragem; poroso continua mais baixo. Sob saturação, impactos enriquecem clusters limitados; clusters velhos são descartados apenas como apresentação acústica, sem apagar massa de sangue. Deadline real de playback é preservado durante reset para evitar reutilização antes de o mixer terminar.

## Compilação, validação e P0

### Erro de compilação corrigido

O comando standalone `--check-only --script res://tests/blood_polish_test.gd` não registra os autoloads da mesma forma que a execução do projeto. O fixture fazia preload do dummy, cujo script usa `Sfx`, e também referenciava `Sfx` diretamente. O erro concreto era `Identifier not found: Sfx`, seguido de `Compilation failed`.

Correção restrita ao fixture: carregar a cena do dummy em runtime, após startup do projeto, usar referência Node3D e obter `/root/Sfx` para cleanup. Nenhuma mudança no comportamento de áudio do dummy. O mesmo comando de parse agora retorna 0.

### Execuções realmente feitas

| Execução | Resultado / interpretação |
|---|---|
| Modelo CPU pequeno | 14 checks, 0 falhas, exit 0 |
| Primeiro fixture headless completo | 45 checks, uma falha; exit 1. O assert lia o último satellite, não a stain central; lookup do contato corrigido. |
| Segundo fixture headless completo | 45 checks, 0 falhas, **signal 11 no encerramento**. O processo retornou 0, mas o backtrace invalida aprovação de estabilidade. |
| Probe de áudio isolado | Uma execução, seis players, um cluster; exit 0 |
| Probe de script/recursos sem `_ready` | Uma execução; exit 0 |
| Probe de BloodSystem vazio | Uma execução; criação e remoção de camadas, sem combate; exit 0 |
| Parse final após correção do fixture | Exit 0 |
| Headless básico final, sem benchmark | 39 checks, 0 falhas, exit 0, sem backtrace |
| **Compatibility básico final** | **Uma única execução**, 48 checks, 0 falhas, seis capturas, áudio não nulo, exit 0, sem backtrace |

Não foram executados loops de stress nativos nem repetidas tentativas até sucesso. Os probes testaram caminhos diferentes e pequenos. O último Compatibility foi deliberadamente básico, depois do parse/headless final, conforme o pedido de fechamento. A suíte completa histórica de movimento não foi reexecutada neste fechamento; preservação fora do sangue foi conferida por hash e diff.

Resultados: [headless final](validation/blood_polish/headless.json), [nativo final](validation/blood_polish/native.json), [estado das execuções](validation/blood_polish/execution_status.json). Os logs preservam também as falhas, não apenas execuções verdes. Persistem mensagens de certificado do ambiente e falha ao gravar cache de shaders; não houve erro de compilação dos shaders no teste Compatibility final.

### Reproducer observado e classificação P0

No projeto atual, o crash foi observado com Godot **4.7.2-stable Steam**, Windows, no término deste comando, sem verbose:

```powershell
& 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --headless --path . res://tests/blood_polish_test.tscn --quit-after 2400
```

O console imprimiu `POLISH: 45 checks, 0 failures` e `POLISH: playback stopped; orderly exit requested`, depois `CrashHandlerException: Program crashed with signal 11`. Trata-se de reprodução **intermitente**, não de promessa de falha em cada execução. O backtrace está em [headless_corrected_console.log](validation/blood_polish/logs/headless_corrected_console.log). A versão final do fixture acrescentou lookup dinâmico de autoload e opção `--basic`; o código final está no workspace, e os logs identificam a execução histórica exata.

**Classificação: causa permanece não identificada.** Falhas de encerramento já estavam documentadas antes deste polish, mas isso não prova identidade de causa nem inocenta todas as mudanças atuais. O ponto observado é teardown após trabalho funcional; não há evidência suficiente para declarar que é somente o harness, somente áudio, driver ou bug do Godot. O binário não forneceu símbolos úteis no backtrace; os probes mínimos não reproduziram o defeito. Não foi aplicada uma suposta correção de memória baseada em adivinhação.

O P0 permanece aberto. A execução final sem crash registra um resultado, **não resolve a intermitência**. A investigação encerra aqui conforme o limite solicitado. Nenhuma afirmação de estabilidade longa, ausência de RAM/VRAM runaway ou aprovação final é feita.

## Performance disponível

Para evitar novos stresses, não foi repetido o benchmark nativo multi-hit anterior. A execução headless completa anterior ao último ajuste de ocupação procedural produziu estes diagnósticos, preservados em [headless_before_final_geometry.json](validation/blood_polish/headless_before_final_geometry.json):

| Releases HIGH_ENERGY | Emit CPU | Média/passo | P95 | Pico/passo | Pico queries | Delta memória estática Godot |
|---:|---:|---:|---:|---:|---:|---:|
| 1 | 0,044 ms | 2,636 ms | 6,589 ms | 8,826 ms | 541 | 512.736 bytes |
| 4 | 0,067 ms | 4,438 ms | 9,461 ms | 13,240 ms | 608 | 950.420 bytes |

São 120 passos por caso, releases controlados de massa 0,5 + tissue 0,1 por vítima, não broadphase/dano de uma luta inteira. **Essa execução crashou ao encerrar.** Os timings continuam dados de diagnóstico, não aprovação do processo. Não são comparação antes/depois equivalente ao benchmark do stability pass. O delta de memória contém estados vivos, não mede leak por sessão, RAM total nem VRAM. O custo esperado do polish é limitado pelos caps e pelo reuso descritos; ganho/perda final de FPS não foi quantificado.

## Capturas e regressões

- [Ângulos 90/60/45/30/15](validation/blood_polish/01_angles.png): marcas irregulares, com alongamento progressivo. O aspecto do quad procedural em 15° passou de aproximadamente 1,05 no diagnóstico anterior para 2,70, sem mudar a física.
- [Fade intermediário](validation/blood_polish/02_fade.png): acompanha os valores de alpha registrados; o teste verifica liberação ao final.
- [Pool após primeira entrada](validation/blood_polish/03_pool_0.png) e [após quatro entradas](validation/blood_polish/03_pool_3.png): crescimento nominal limitado por novas entradas.
- [Fan de slash](validation/blood_polish/04_slash_fan.png) e [aftermath de slash](validation/blood_polish/05_slash_aftermath.png): captura dos mesmos droplets e do footprint específico, sem ribbon extra.

As capturas não são first-person acceptance. O dummy aparece escuro/branco por iluminação/flash do fixture congelado; isso não altera o material do jogo. Trajetória, distinção sutil da cauda e mixagem sob combate exigem inspeção manual em movimento.

Regressões adicionadas: limite não letal e conservação; três sequências de dano através do caminho real; admissão, representantes e stains por event ID; ângulos e tangente de chão; fade por pressão e proteção do material fresco; crescimento por crédito e parada; slash preservando STREAK; wake ausente em velocidades baixas/fine e maior em slash; 1/10/100 impactos em uma voz; caps de áudio/fade/pool/queries e capacidade fixa do MultiMesh. Nem todos esses asserts substituem julgamento visual, nem são prova de ausência de crash.

## Arquivos deste passe

Modificados, comparados ao snapshot inicial do polish:

- `gameplay/combat/blood_reservoir.gd`
- `gameplay/combat/reservoir_config.gd`
- `presentation/gore/blood_impact_audio_accumulator.gd`
- `presentation/gore/blood_liquid.gdshader`
- `presentation/gore/blood_multimesh_layer.gd`
- `presentation/gore/blood_stability_settings.gd`
- `presentation/gore/blood_stain.gdshader`
- `presentation/gore/blood_system.gd`

Novos:

- `tests/blood_polish_model_test.gd` e `.gd.uid`
- `tests/blood_polish_test.gd`
- `tests/blood_polish_test.tscn`
- `tests/blood_shutdown_probe.gd`
- `docs/BLOOD_POLISH_PASS.md`
- Evidências em `docs/validation/blood_polish/`, enumeradas no manifesto de artefatos.

`git diff --check` passou. Os novos controles estão no schema já carregado; não foi necessário alterar `.tres`, projeto, armas, movimento ou outra arquitetura.

## Checklist de aceitação manual no Godot

O P0 continua pendente; o checklist descreve a aceitação que falta e não declara a build estável. Interrompa o teste se aparecer erro de memória/crash; preserve o log, sem repetir stress até passar.

1. Abra `world/chambers/prototype/the_box.tscn` em **Compatibility**, F6. Deixe F4 desligado para leitura visual/performance. Para comparação por família, use `world/chambers/blood_lab/blood_lab.tscn`, teclas 1–4.
2. Twin Daggers: corte nos dois sentidos. Procure fan lateral, pequenos streaks e cast-off acompanhando o swing, claramente diferentes de Hand Cannon, Maul e explosão.
3. Faça marcas persistentes, continue contaminando a cena e observe marcas antigas: fade gradual, sem apagar imediatamente impactos recém-criados. F4 mostra fades ativos/limite para diagnóstico.
4. Compare impactos de frente e rasantes no chão e na parede. O eixo/tail deve seguir a aproximação; bordas devem ser irregulares sem perder ancoragem.
5. Observe medium/large rápidos: cauda curta, carmesim, sem glow/laser/blur excessivo. Material lento e micro não deve exibir wake caro.
6. Deixe gotas repetidas caírem no mesmo ponto: base cresce por entradas. Interrompa a fonte; após a acomodação curta, não deve continuar expandindo. Um grão pequeno não deve liberar sozinho uma poça gigante.
7. Ouça gotas maiores isoladas e uma chuva densa. Deve haver tick/textura molhada audível e irregular; tiros e impactos de combate devem continuar dominantes. Confira superfície porosa mais abafada.
8. Acerte um dummy na periferia de uma explosão para ele sobreviver. Depois atire nele; repita com Daggers. Dano aceito deve continuar gerando sangue e deposição. Compare também BLUNT não letal → BALLISTIC.
9. Confira runoff contínuo, chegada ao chão, Maul nos dois sentidos, identidade explosiva e paleta aprovada. Nenhuma dessas características deve ter regredido.
10. Observe profiler e memória numa sessão curta, sem stress repetitivo: fades ≤128, trail slots ≤96, vozes ≤6, clusters ≤32. Registre qualquer hitch ou crescimento persistente de memória; a medição automatizada desta entrega não cobre endurance.

**Não concluído:** isolamento/correção definitiva do crash P0, endurance de RAM/VRAM, novo benchmark nativo comparável antes/depois, assets/mixagem finais e aprovação visual em primeira pessoa. Implementação e relatório encerrados neste ponto, sem outro ciclo de polish.
