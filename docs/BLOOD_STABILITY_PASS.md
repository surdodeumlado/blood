# Blood System — estabilidade, superfícies e multi-hit

Implementação incremental sobre a versão carmesim existente. Não houve nova pesquisa nem mudança de direção artística. A aprovação visual e sonora depende do playtest do jogador.

## As oito reclamações

| Reclamação | Causa encontrada | Implementação e resultado observado | Limitação restante |
|---|---|---|---|
| 1. Manchas atravessando/flutuando em paredes | Um contato válido no centro não validava o restante do quad; reforços e segmentos podiam ampliar esse problema. Não havia ownership geométrico suficiente. | Contato reprojetado, normal medida, offsets de 1–2,5 mm, collider e frame tangente persistidos. Centro + oito amostras do footprint; redução conservadora ou rejeição. Leitura nativa do MultiMesh confere com o transform submetido. Mudança, remoção, desativação e edição da forma invalidam a marca. | É amostragem planar conservadora, não recorte exato de malha. Pequenos buracos entre amostras e superfícies curvas muito irregulares ainda exigem avaliação. Geometria movida perde as marcas antigas, em vez de carregá-las. |
| 2. Depósitos molhados importantes não escorriam | A tentativa de iniciar runoff dependia do recebimento pontual do depósito; não havia avaliação contínua da massa local acumulada e retenção. | Patches com massa molhada/absorvida, idade, orientação, footprint e material. Estados `STATIC_WET`, `RUNOFF_ELIGIBLE`, `RUNNING`, `ABSORBING`, `DRY_OR_EXHAUSTED`. Depósitos pesados lisos e rugosos iniciam após atraso limitado; poroso absorve; gotas pequenas ficam estáticas. Capturas mostram os filetes conectados. | Modelo fenomenológico; não resolve filme líquido nem ângulo de contato dinâmico. Novos fluxos podem esperar pelo limite global de 24 rivulets. |
| 3. Hitch imediato em multi-victim | Cada vítima emitia todas as camadas e fazia deposição síncrona. Havia três chamadas individuais ao RenderingServer por escrita, diagnóstico de cobertura no caminho de produção e busca repetida de células para expulsão. | Fila de apresentação em três passos, densidade adaptativa, prioridades, colisões agrupadas, reservas de queries e upload único por camada/frame. O dano continua imediato. Medições completas abaixo. | A validação de suporte custa CPU e aumenta a média de alguns casos de uma vítima. O pico de primeiro uso nativo permanece uma limitação separada. |
| 4. Manchas grandes borradas | Ampliação de atlas pequeno e reforços grandes sem preservar detalhe de borda. | Atlas existente e filtragem linear preservados para marcas pequenas. Acima do limite de densidade, máscara procedural com borda antialiasada, variação espacial sem padrão radial repetido, base escura e marcas menores sobrepostas. Satellites de splash continuam sujeitos à física e ao orçamento. | Não é um material fotográfico. A máscara e a sobreposição ainda precisam da avaliação artística em THE_BOX; transparência sobreposta pode custar fill rate. |
| 5. Manchas gigantes surgindo prontas | Reforço por densidade de célula ampliava o próximo depósito; deposição grosseira não distinguia bem impacto direto e acúmulo. | Removido o multiplicador aleatório por célula. Limites por classe e residual. Footprint grande imediato exige marcação catastrófica e massa suficiente; suporte continua obrigatório. | Uma morte catastrófica ainda pode produzir uma marca imediata grande por decisão explícita. As dimensões configuradas de stain são nominais de apresentação, não medidas forenses. |
| 6. Poças não cresciam | A base era criada diretamente no tamanho final quando cruzava um limiar. | `target_pool_area` derivada de massa, `rendered_pool_area` separada, início pequeno e expansão por janela curta renovada por novas entradas. Compensação de ocupação da máscara evita esconder todo crescimento sob o detalhe. Runoff que encontra o chão transfere massa para a contaminação real do chão. | Existe uma acomodação de até 0,3 s depois da última entrada; depois disso não há crescimento autônomo. Limites e suporte podem impedir alcançar a área alvo. Área nominal não equivale a cobertura única dos pixels. |
| 7. Ghost bleeding | Handoff usava posições genéricas e várias wounds podiam receber o mesmo orçamento de remnant sem debitá-lo. Faltava validar explicitamente vida/visibilidade/geração do dono. | Wound viva segue transform local válido. Morte captura a posição da própria wound, debita a massa transferida uma vez e remove ownership vivo. Remnants têm suporte final, reserva e prazo finitos. Respawn esgota wounds antigas. Gotejamento vivo não fica aguardando na fila de bursts com transform antigo. | O remnant é uma fonte biológica virtual curta que desce ao suporte final, não um corpo de tecido simulado. Material residual não emitido ao encerrar permanece contabilizado como retido. |
| 8. Falta de textura sonora das gotas | Não existia acumulação acústica por impacto. | Acumulador espacial/temporal, 80 ms e células de 1,2 m; seis players 3D reutilizados, no máximo dois novos eventos/frame e 32 clusters. Cem impactos próximos geram uma textura agregada. Contagem aumenta densidade, não volume linear. | Áudio sintetizado provisório. A execução nativa usa driver Dummy para medir CPU; não é aprovação auditiva nem validação da mixagem contra combate. |

## Física, massas e apresentação preservadas

- Paleta aprovada preservada: `#DC143C` fresh, `#A80D30` dark fresh, `#FF526C` wet highlight e `#690A24` pooled já existentes. Os recursos de paleta e física são idênticos ao snapshot inicial desta etapa.
- Diâmetro físico, drag por diâmetro, gravidade, breakup limitado, bases de direção, morph por incidência e generators de arma continuam na arquitetura existente.
- Massa usa unidades normalizadas do reservatório, **não litros**. Redução de amostragem aumenta massa representada por parcel; não muda o dano nem o volume lógico retirado.
- Impactos próximos compartilham apresentação em células de 0,3 m, mantendo um ponto de colisão verdadeiro, normal e collider; não calculamos um centro médio que possa atravessar uma quina.
- Contact records ligam drop/event → cluster → stain. Coarse e overflow são explicitamente identificados. Sem suporte, massa fica no estoque retido; sem hit de coarse, em `escaped_mass`. Isto é contabilidade explícita, não promessa de que todo material se tornou pixel visível.
- Preservados atlas por variante, superfícies floor/wall/ceiling, cast-off e direções +X/−X do Maul. Líquido continua arredondado; tissue permanece uma camada sólida distinta.

## Orçamentos e escalonamento

Os limites são compartilhados entre passos de física do mesmo frame renderizado, inclusive catch-up. Uma opção de relógio manual existe exclusivamente para fixtures.

| Recurso | Limite padrão |
|---|---:|
| Queries de sangue, incluindo suporte/coarse | 640/frame |
| Reserva para superfície | 128 queries |
| Queries de sólidos | 64/frame |
| Novos parcels físicos, incluindo breakup/drips | 192/frame |
| Novos sólidos | 72/frame |
| Micro elementos | 128/frame |
| Escritas de stains/pools/segmentos | 48/frame |
| Novos rivulets | 4/frame; 24 simultâneos |
| Novos terminal wall drops | 4/frame |
| Fila de releases / contatos / coarse | 64 / 512 / 128 |
| Uploads MultiMesh | 1 por camada/frame; 5 camadas |
| Vozes / novos eventos de áudio | 6 simultâneas / 2 por frame |

Burst: passo 0 prioriza medium/globs, sólidos e agenda coarse; passo 1 adiciona small; passo 2 micro. A densidade do grupo próximo usa `max(0.28, 1 / (1 + 0.32 * (vizinhos - 1)))`, depois considera distância e admissões livres. O orçamento compartilhado pode reduzir ainda mais as contagens. Kills, headshots, explosões e proximidade aumentam prioridade de releases; globs/large e medium próximos recebem queries antes de fine/distant.

Quando não há capacidade, o material segue como coarse pendente, estoque retido ou escape declarado. Espera de query é limitada; não há simulação física por Node/RigidBody individual. Coalescing extremo pode perder detalhe da assinatura de uma vítima, mas não sua massa lógica. O orçamento não elimina o custo de simular/renderizar elementos ainda vivos.

Não foi encontrado upload de **buffer inteiro por vítima** no código anterior: eram chamadas por instância. O pass substitui essas chamadas por escrita em array CPU e commit consolidado. Os timings de emissão anteriores já cresciam menos que linearmente em parte dos cenários por causa dos caps; não há evidência para atribuir o hitch a uma única fórmula superlinear. O problema medido era o volume de trabalho síncrono e as operações repetidas dentro dele.

## Benchmark nativo

Godot 4.7.2, Compatibility, 1280×720, Ryzen 5 3600, Radeon RX 9060 XT, vsync desativado. O fixture usa `Weapon.apply_hit`, hurtboxes reais e reservatórios de DummyTarget, com contatos já resolvidos de BLUNT/HIGH_ENERGY. Cada cenário avança 360 passos de 1/60 s e desenha frames reais. **Não inclui broadphase do swing/granada, movimentação do jogador nem uma luta completa.** Não há medição de GPU.

Os timers são CPU instrumentada, com overhead de observação. São execuções controladas antes/depois, não intervalos estatísticos de várias máquinas. `native_frame_peak_ms` inclui o intervalo observado ao renderizar e a emissão no primeiro passo; não equivale a GPU time. A fixture congela a animação dos dummies, que aparecem brancos nas capturas; isso não é uma alteração do material dos inimigos.

Dados brutos: [antes](validation/blood_stability/before/multi_hit.json), [depois](validation/blood_stability/after/multi_hit.json). Valores das tabelas são gerados desses arquivos, sem excluir o primeiro evento.

Cada célula com seta mostra **antes → depois**. Tempos em ms.

| Família | Vítimas | Emissão CPU | Média do passo | P95 do passo | Pico do passo | Pico nativo observado |
|---|---:|---:|---:|---:|---:|---:|
| BLUNT | 1 | 19.636 → 0.324 | 1.532 → 2.086 | 6.171 → 6.571 | 13.247 → 10.221 | 435.502 → 683.158 |
| BLUNT | 2 | 33.706 → 0.332 | 2.435 → 2.694 | 10.705 → 7.739 | 19.734 → 11.536 | 46.582 → 12.130 |
| BLUNT | 4 | 51.061 → 0.437 | 3.695 → 3.322 | 13.002 → 8.932 | 29.952 → 10.686 | 70.519 → 12.100 |
| BLUNT | 8 | 88.219 → 0.646 | 5.333 → 4.017 | 19.234 → 9.741 | 51.522 → 12.445 | 115.767 → 13.365 |
| HIGH_ENERGY | 1 | 21.616 → 0.213 | 2.510 → 3.047 | 5.324 → 6.521 | 19.003 → 12.867 | 30.871 → 13.846 |
| HIGH_ENERGY | 2 | 36.394 → 0.288 | 4.729 → 4.280 | 12.064 → 8.980 | 37.711 → 13.982 | 52.123 → 14.899 |
| HIGH_ENERGY | 4 | 59.030 → 0.411 | 7.114 → 4.872 | 16.662 → 10.651 | 82.258 → 15.602 | 84.286 → 17.008 |
| HIGH_ENERGY | 8 | 96.805 → 0.843 | 8.013 → 5.564 | 17.883 → 13.200 | 96.991 → 17.856 | 126.293 → 18.895 |

| Família | Vítimas | Parcels físicos no pico | Queries totais | Pico queries/passo | Escritas de stains totais | Pico escritas/passo | Commits depois: total / pico por frame |
|---|---:|---:|---:|---:|---:|---:|---:|
| BLUNT | 1 | 567 → 484 | 59807 → 37177 | 1236 → 608 | 2209 → 1032 | 182 → 21 | 830 / 5 |
| BLUNT | 2 | 827 → 533 | 89817 → 48162 | 1669 → 608 | 3551 → 1565 | 280 → 22 | 898 / 5 |
| BLUNT | 4 | 1130 → 505 | 124899 → 54747 | 1996 → 608 | 4699 → 2437 | 625 → 32 | 922 / 5 |
| BLUNT | 8 | 1687 → 423 | 183345 → 61860 | 2528 → 608 | 6242 → 3155 | 1122 → 37 | 1226 / 5 |
| HIGH_ENERGY | 1 | 596 → 435 | 110176 → 52720 | 1349 → 608 | 2831 → 819 | 330 → 27 | 1200 / 5 |
| HIGH_ENERGY | 2 | 1062 → 481 | 189613 → 73147 | 2034 → 608 | 5167 → 1231 | 695 → 21 | 1281 / 5 |
| HIGH_ENERGY | 4 | 1582 → 488 | 270038 → 79477 | 2584 → 610 | 7218 → 1908 | 1425 → 22 | 1292 / 5 |
| HIGH_ENERGY | 8 | 1720 → 405 | 292365 → 80139 | 2762 → 619 | 8240 → 2588 | 1719 → 32 | 1324 / 5 |

Antes, os buffer commits eram zero porque o código usava a API por instância. No caso HIGH_ENERGY ×8 foram **1.023.084 chamadas individuais**, agora zero; há no máximo cinco submits de buffer por frame. Os parcels da tabela incluem breakup e sobrevivência, não apenas admissões na origem.

Na emissão original de HIGH_ENERGY ×8: 30,690 ms em physical admission, 9,674 ms em tissue, 17,075 ms em micro e 36,174 ms em coarse. Dentro do trabalho de deposição havia 16,402 ms de diagnóstico de cobertura. Hit resolution e reservoir withdrawal somavam apenas 0,519 ms. Esses números localizam o custo no blood presentation, sem atribuí-lo ao dano ou ao broadphase não medido.

O primeiro BLUNT teve pico nativo de **435,502 → 683,158 ms**, muito maior que seu passo CPU. A fixture padrão pode limpar os buffers de prewarm antes de seu primeiro desenho. Um [controle separado](validation/blood_stability/warm_control/multi_hit.json), esperando três frames de desenho antes de limpar, gastou **841,161 ms no preparo inicial** e mediu depois **11,131 ms de pico nativo no primeiro BLUNT** (emissão 0,250 ms). O custo foi deslocado para o preparo, não apagado nem excluído da tabela principal. Os logs também registram falha de cache de shaders; não isolamos o tempo de GPU/driver. O prewarm de produção foi preservado. É preciso conferir o primeiro hit em THE_BOX depois de carregar, especialmente sem cache. Também não afirmamos que toda média melhorou: suporte e wet patches introduzem trabalho adicional nos cenários leves.

`all_stages_us` inclui hit resolution, reservoir withdrawal, pattern sampling, physical/tissue admission, coarse, raycasts, wet patches e áudio. Depois também separa queue, simulação física/sólida, runoff, clusters e pools. `instance_write_cpu_us` e `buffer_submit_cpu_us` medem escrita CPU e submissão das cinco camadas. Timers internos são aninhados: não somar todas as colunas como se fossem custos independentes.

## Suporte, runoff e pooling

`BloodSurfaceSupport` usa offsets em metros: detail 0,0025; pool 0,001; runoff 0,002. Raios curtos de ±0,065 m verificam normal (dot ≥0,985), collider e concordância com o plano (tolerância 0,012 m). O footprint é testado até quatro reduções de fator 0,55; falha final rejeita a marca. A política vale também para segmentos e atualizações de pool. Ownership inclui assinatura consultada das CollisionShape3D e de seus dados geométricos, sem callbacks de Shape3D durante destruição. Para malhas complexas, calcular essa assinatura pode custar mais que nas primitivas usadas em THE_BOX.

Runoff compara gravidade tangente e massa disponível com retenção efetiva da superfície e footprint. Exige ainda o limiar mínimo existente. O atraso é `clamp(delay_max / ratio, 0.06, 0.35)`. Absorção dominante toma precedência. A revisão de depósito impede reiniciar indefinidamente o mesmo estoque; uma nova entrada pode reativar o patch. O filete é contínuo, afina com o estoque restante e termina ao gastar a reserva ou cumprir o prazo. Ao atingir chão real, o restante é transferido a esse contato; ao perder a parede, vira terminal drop físico ou coarse limitado.

Pools começam com área nominal de até 0,012 m², após 0,018 unidade de massa local; alvo de 4,5 m²/unidade, limitado a 1,5 m²/patch. Crescimento limitado a 2,5 m²/s, somente durante a janela financiada por entrada recente. A máscara ocupa aproximadamente 75% do diâmetro do quad; sua compensação afeta só apresentação, nunca massa. Os parâmetros de área não são uma medida de cobertura única: sobreposições e máscara reduzem a cobertura real.

Para manchas maiores que a densidade mínima de 160 texels/m do atlas de 64 px/célula, a borda passa a ser procedural. A base escura, os contatos menores sobrepostos e até dois satellites por impacto de splash importante fornecem escalas distintas de detalhe, sempre dentro do orçamento. Micro detalhe é o primeiro a ceder.

## Áudio

`BloodImpactAudioAccumulator` recebe posição, superfície, massa representada, velocidade, classe e timestamp. A janela é medida desde o primeiro impacto do cluster, não estendida eternamente por cada gota. Overflow enriquece clusters existentes; uma voz disponível reproduz tick ou textura densa com transientes irregulares. Pitch varia de maneira limitada; volume parte de −30 dB, com teto −21 dB; poroso reduz mais 4 dB. Distância máxima: 18 m. Superfícies mapeiam para hard/smooth (inclui metal), rough, porous e wall hard. Não há banco distinto para cada material físico.

Uma voz só é reutilizada depois de vencerem seu prazo de simulação e seu prazo real de reprodução, e quando o player não está mais tocando. Isso evita substituir playback ainda ativo durante catch-up ou simulação acelerada. O cap permanece seis players, incluindo essas vozes aguardando o mixer.
Os WAV de referência [gota](validation/blood_stability/fixtures/placeholder_single.wav) e [chuva](validation/blood_stability/fixtures/placeholder_rain.wav) são gerados pelo próprio placeholder. Os hooks são os streams do acumulador. A versão final depende de sound design e escuta em combate.

## Validação e capturas

| Fixture | Resultado final |
|---|---|
| Stability headless | 46 checks, 0 falhas funcionais; encerramento intermitente com access violation, ver abaixo |
| Stability nativo | 55 checks, 0 falhas; oito capturas + readback MultiMesh; exit 0 |
| Material físico | 49 checks, 0 falhas funcionais; encerramento intermitente com access violation, ver abaixo |
| Phase 2 / 2.1 / 2.2 / 2.3 | 68 / 56 / 39 / 59 checks, todos sem falhas |
| Movement/combat smoke | 154 checks, 0 falhas; bhop, slide, dash, tiro, melee, grenade e selector |

As áreas nominais do pool na sequência de entradas foram 0 → 0,108 → 0,162 → 0,216 → 0,270 m². A captura de perto mostra a borda escura se expandindo ao redor do detalhe residual. Os testes também cobrem edição/movimento de collider, runoff para o chão, oito vítimas, catch-up compartilhando budgets, conservação de overflow e 100 impactos agrupados em uma voz.

A fixture de movement continua com apresentação assíncrona real; somente os asserts de sangue foram atualizados para esperar três passos e comparar massa aceita, não partículas. Nenhuma regra de movimento/arma foi alterada para fazê-la passar.

Os logs não mostram exceções de GDScript, mas isso não significa processo totalmente aprovado: há falha nativa de encerramento nos dois fixtures headless descrita abaixo. Persistem diagnósticos do ambiente sobre certificados/cache de shaders; o movement smoke registra o aviso preexistente de duas instâncias ObjectDB no encerramento. `git diff --check` passou. Resultados estruturados: [regressions.json](validation/blood_stability/regressions.json), [stability nativo](validation/blood_stability/fixtures/native_results.json), [material](validation/blood_stability/material/results.json).

**Pendência de encerramento:** os fixtures acelerados de stability e material concluem os asserts e escrevem seus resultados, mas a última rodada headless sem verbose terminou com `-1073741819` (`0xC0000005`) após solicitar saída. Duas execuções com verbose e a mesma implementação terminaram com 0; isso não comprova correção. A captura Compatibility final e o benchmark nativo terminaram com 0. Foi acrescentada proteção contra reutilização de áudio ainda ativo, encerramento explícito do blood e espera real de 0,5 s nos fixtures; o crash headless persistiu. O log não fornece stack nativa. Não foi isolada a causa entre engine, teardown de recursos e apresentação: **não atribuímos o crash ao áudio como causa comprovada, nem declaramos estabilidade completa**. Os resultados funcionais e códigos de saída estão separados em [teardown_runs.json](validation/blood_stability/teardown_runs.json).
A suíte nova usa a fila e os budgets reais. Fixtures históricas que verificam contratos imediatos usam `synchronous_test_mode` e relógio manual; portanto suas contagens **não são benchmarks da apresentação em produção**. Os testes antigos de runoff agora esperam o atraso físico limitado antes de exigir um filete. A comparação de exaggeration usa massa abaixo do novo cap para não medir duas stains já saturadas no mesmo limite.

Capturas nativas e readback: [suporte de borda](validation/blood_stability/fixtures/01_supported_edge.png), [paredes em 0,5 s](validation/blood_stability/fixtures/02_wall_half_second.png), [filetes terminados](validation/blood_stability/fixtures/03_wall_finished.png), [pool inicial](validation/blood_stability/fixtures/04_pool_1.png), [pool após entradas](validation/blood_stability/fixtures/04_pool_4.png), [quatro vítimas HIGH_ENERGY](validation/blood_stability/after/HIGH_ENERGY_4_359.png). Arquivos `*_2.png` e `*_359.png` registram início e aftermath dos oito cenários nativos. Não substituem seu playtest em primeira pessoa.

F4 mantém o modo de desenvolvimento existente e acrescenta orçamento usado, filas, wet mass/state, normal e pontos de suporte recentes, fontes/remnants e massa restante, clusters e limite de áudio. Não é HUD de produção; o próprio modo de debug tem custo adicional e deve ficar desligado nos testes de performance.

## Parâmetros e arquivos

Todos os novos controles de produção ficam em [BloodStabilitySettings](../presentation/gore/blood_stability_settings.gd), carregado por [blood_stability.tres](../data/blood/blood_stability.tres). Grupos: limites/frame e filas, densidade/prioridade, suporte e offsets, limites imediatos por classe, wetness/runoff, crescimento/ocupação de pool e áudio. Os valores completos estão no recurso; os defaults relevantes estão nas tabelas acima. Não há parâmetros novos de dano, cooldown, movimento ou FOV.

Modificados nesta etapa:

- `gameplay/combat/blood_reservoir.gd`
- `gameplay/combat/wound.gd`
- `gameplay/enemies/dummy_target.gd`
- `gameplay/weapons/weapon.gd`
- `presentation/gore/blood_multimesh_layer.gd`
- `presentation/gore/blood_settings.gd`
- `presentation/gore/blood_stain.gdshader`
- `presentation/gore/blood_system.gd`
- `tests/blood_material_test.gd`
- `tests/blood_phase2_test.gd`
- `tests/blood_phase21_test.gd`
- `tests/blood_phase22_test.gd`
- `tests/blood_phase23_test.gd`
- `tests/movement_smoke_test.gd`

Novos nesta etapa:

- `data/blood/blood_stability.tres`
- `docs/BLOOD_STABILITY_PASS.md`
- `presentation/gore/blood_impact_audio_accumulator.gd`
- `presentation/gore/blood_impact_audio_accumulator.gd.uid`
- `presentation/gore/blood_stability_settings.gd`
- `presentation/gore/blood_stability_settings.gd.uid`
- `presentation/gore/blood_surface_support.gd`
- `presentation/gore/blood_surface_support.gd.uid`
- `tests/blood_multi_hit_test.gd`
- `tests/blood_multi_hit_test.gd.uid`
- `tests/blood_multi_hit_test.tscn`
- `tests/blood_stability_test.gd`
- `tests/blood_stability_test.tscn`

Artefatos adicionais: `docs/validation/blood_stability/` contém os JSON, capturas e WAV desta entrega. A lista exata de todos os artefatos fica em `artifact_manifest.txt`; a prova de escopo está em [scope_manifest.json](validation/blood_stability/scope_manifest.json).

O workspace já continha alterações das etapas anteriores. A lista desta entrega é comparada por SHA-256 com o snapshot do início desta etapa, não inferida indiscriminadamente de `git diff HEAD`. Os arquivos de movimento, câmera/FOV, selector, regras Maul/granada, configs de dano/tempo, paleta, profiles e física anteriores permaneceram idênticos ao snapshot. Em `weapon.gd` mudaram apenas timers opt-in e transferência do remnant; em `dummy_target.gd`, a posição/handoff das wounds. Não houve commit nem alteração de gameplay autorizada por extrapolação.

## Pendências e limites explícitos

- Falha nativa intermitente ao encerrar os fixtures headless de stability/material permanece sem causa isolada. Os asserts passam, mas esses processos não recebem aprovação total; o último ciclo nativo terminou normalmente.
- Aprovação visual de primeira pessoa e aprovação auditiva pertencem ao jogador.
- Assets finais de áudio e equilíbrio da mixagem com combate não foram concluídos; há placeholders funcionais.
- O preparo nativo a frio continua custoso: o controle desloca aproximadamente 0,84 s para os frames iniciais. Falta validar esse carregamento/primeiro hit em THE_BOX; não há isolamento de GPU/driver nem garantia de frame time em outras máquinas.
- Benchmark mede contatos reais já resolvidos, não o broadphase completo de Maul/granada nem uma sessão longa de gameplay. A regressão de movimento é separada.
- Suporte é planar e amostrado. Mover/editar geometria remove marcas antigas; não deforma decals junto à malha.
- Sob saturação extrema, coarse/retained/escaped preservam contabilidade, mas não todos os detalhes visuais. Não há promessa de um decal por gota.
- As métricas de áreas são aproximações geométricas; não são m² de cobertura única visível, nem validação forense.

## Checklist exato de playtest no Godot

1. Abra o projeto no renderer **Compatibility**. Execute `world/chambers/prototype/the_box.tscn` com F6 ou F5 no projeto; use a qualidade INSANE atual. Deixe **F4 desligado** ao avaliar performance. Anote separadamente o primeiro hit após abrir a sessão.
2. Encoste alvos em paredes e quinas; use Hand Cannon e Maul. Caminhe de frente, de lado e em ângulo raso. Manchas devem ficar flush, sem quads atravessando bordas ou pairando; bordas sem suporte podem produzir marcas menores.
3. Compare gotas pequenas e depósitos pesados na parede. Pequenas podem parar; heavy wet deve iniciar runoff após um atraso curto. Observe a ligação contínua à fonte, o afinamento e a chegada ao chão. Para comparar smooth, rough e porous de forma controlada, rode `tests/blood_stability_test.tscn` com F6 e consulte as capturas; para exploração por arma, use `world/chambers/blood_lab/blood_lab.tscn`, teclas 1–4.
4. Repita gotas/deposição no mesmo local. A base escura deve aparecer pequena e crescer com novas entradas; interrompa o fluxo e confira que para após a curta acomodação. Impactos realmente catastróficos podem deixar uma marca grande imediata.
5. Aproxime-se do aftermath grande: bordas irregulares devem permanecer nítidas, com detalhe sobreposto; sem blur de bitmap gigante. Confira o carmesim aprovado, líquido arredondado e tissue separado.
6. Fira um dummy, desloque-o, mate/remova-o e aguarde o respawn. Gotas vivas devem seguir o alvo; remnant pode produzir apenas uma sequência curta, finita. Aguarde pelo menos 10 s: nenhuma fonte fantasma deve continuar fabricando stains gigantes.
7. Com o profiler do Godot aberto, compare Maul em **1, 2 e 4 alvos** próximos; depois granada com **1, 4 e 8 vítimas**. Observe o pico de frame do impacto e os segundos seguintes. A redução de detalhe deve manter direções e aftermath claros. Repita o mesmo caso depois do primeiro uso.
8. Repita BALLISTIC, SLASHING, BLUNT nos dois sentidos do swing e HIGH_ENERGY por vítima. Verifique spray forward/back, arco/cast-off, momentum do Maul, parede/chão/teto e a consequência ambiental.
9. Com volume normal, ouça gotas maiores isoladas e uma chuva densa. Devem produzir ticks discretos/textura molhada suave, sem centenas de sons separados; tiros e impactos de combate devem permanecer dominantes.
10. Ative **F4** só para diagnóstico: queries ≤640/frame, novas vozes ≤2/frame, simultâneas ≤6; compare estado/massa dos patches e fontes de remnant. Desative F4 para a decisão final de performance e leitura visual.

Este pass encerra aqui. Os resultados documentam implementação, regressões e observações de captura; **não constituem aprovação visual, sonora ou validação forense**.
