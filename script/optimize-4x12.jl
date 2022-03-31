# %% [markdown]
"""
# ColorScheme Optimizer

以下の戦略に基づき最適化。

- 視認性を担保する制約条件
  - 任意の bg と fg のペアにおいて、輝度 (L) 差が一定以上
  - 任意の bg と fg のペアにおいて、l2ノルムが一定以上
- 識別性を最大化する目的関数
  - なるべく bg 同士、 fg 同士の距離（l2ノルム）が大きくなるようにする
  - 上記距離の最小値を最大化する

- `fg_base` と `fg_colored`, `bg_base` と `bg_colored` を用意
- `*_base` は基本色。 `*colored` は色づいたもの。
- `*_base` と他の色の間にはくっきりとした区別がつくようにする。視認性も高める。
- `*_colored` 同士はちょっと視認性などの条件を控えめにしておく。
"""

# %%
using OptimalColor
using Crayons
using Plots
using JuMP
using Printf
using DataFrames

plotly()

# %%
model_config = ModelConfig(
# n_bg: 欲しい background color の数 (base 除く)
n_bg = 3,
# n_fg: 欲しい foreground color の数 (base 除く)
n_fg = 11,
# bbase と f、b と fbase の間に担保される L* の差（視認性の担保）
d_vivid_base = 32,
# f、b 間に担保される L* の差（視認性の担保）
d_vivid_colored = 28,
# margin: 純色（RGB 色空間の境界面に位置する色）を避けるため、
#         RGB 色空間の端に設けるマージン。
margin = 16 / 255,
# b が満たすべき色相の差（色相の多様性の担保）
min_theta_bg = 70 * π / 180,
# f が満たすべき色相の差（色相の多様性の担保）
min_theta_fg = 25 * π / 180,
# b 同士の Lab 色空間上における最低距離（識別性の担保）
min_dist_b = 36,
# f 同士の Lab 色空間上における最低距離（識別性の担保）
min_dist_f = 36,
)

model = new_model(model_config)

# %%
optimize!(model)

# %% [markdown]
"""
## 結果の可視化
"""

# %%
# 目的関数の値
@show termination_status(model)
@show objective_value(model)

# %%
b = model[:b]
f = model[:f]
bbase = model[:bbase]
fbase = model[:fbase]
bmat = UInt8.(round.(value.(b) * 255))
fmat = UInt8.(round.(value.(f) * 255))
bbasemat = UInt8.(round.(value.([bbase, bbase, bbase]) * 255))
fbasemat = UInt8.(round.(value.([fbase, fbase, fbase]) * 255))
bmat = [reshape(bbasemat, (1, 3)); bmat]
fmat = [reshape(fbasemat, (1, 3)); fmat]

for j in 1:model_config.n_fg+1
    for i in 1:model_config.n_bg+1
        c = Crayon(
        foreground = (fmat[j, 1], fmat[j, 2], fmat[j, 3]),
        background = (bmat[i, 1], bmat[i, 2], bmat[i, 3])
        );
        print(c("Hello, world!"))
        print("  ")
    end
    println()
end

# %%
for j in 1:model_config.n_bg+1
    for i in 1:model_config.n_bg+1
        c = Crayon(
        foreground = (fmat[1, 1], fmat[1, 2], fmat[1, 3]),
        background = (bmat[j, 1], bmat[j, 2], bmat[j, 3])
        );
        print(c("foo bar "))
        c = Crayon(
        foreground = (fmat[1, 1], fmat[1, 2], fmat[1, 3]),
        background = (bmat[i, 1], bmat[i, 2], bmat[i, 3])
        );
        print(c(" foo bar "))
        c = Crayon(
        foreground = (fmat[1, 1], fmat[1, 2], fmat[1, 3]),
        background = (bmat[j, 1], bmat[j, 2], bmat[j, 3])
        );
        print(c(" foo bar"))
        print("  ")
    end
    println()
end

# %%
α = 0.15
bmat_transparent = UInt8.(round.(bmat * (1 - α) .+ 255 * α))
for j in 1:model_config.n_fg+1
    for i in 1:model_config.n_bg+1
        c = Crayon(
        foreground = (fmat[j, 1], fmat[j, 2], fmat[j, 3]),
        background = (bmat_transparent[i, 1], bmat_transparent[i, 2], bmat_transparent[i, 3])
        );
        print(c("Hello, world!"))
        print("  ")
    end
    println()
end

# %%
for j in 1:model_config.n_bg+1
    for i in 1:model_config.n_bg+1
        c = Crayon(
        foreground = (fmat[1, 1], fmat[1, 2], fmat[1, 3]),
        background = (bmat_transparent[j, 1], bmat_transparent[j, 2], bmat_transparent[j, 3])
        );
        print(c("foo bar "))
        c = Crayon(
        foreground = (fmat[1, 1], fmat[1, 2], fmat[1, 3]),
        background = (bmat_transparent[i, 1], bmat_transparent[i, 2], bmat_transparent[i, 3])
        );
        print(c(" foo bar "))
        c = Crayon(
        foreground = (fmat[1, 1], fmat[1, 2], fmat[1, 3]),
        background = (bmat_transparent[j, 1], bmat_transparent[j, 2], bmat_transparent[j, 3])
        );
        print(c(" foo bar"))
        print("  ")
    end
    println()
end

# %%
df = DataFrame(r=[], g=[], b=[], kind=[])
for i in 1:model_config.n_bg+1
    color = @sprintf("#%02x%02x%02x", bmat[i, 1], bmat[i, 2], bmat[i, 3]);
    push!(df, [bmat[i, 1], bmat[i, 2], bmat[i, 3], color])
end
for i in 1:model_config.n_fg+1
    color = @sprintf("#%02x%02x%02x", fmat[i, 1], fmat[i, 2], fmat[i, 3]);
    push!(df, [fmat[i, 1], fmat[i, 2], fmat[i, 3], color])
end

Plots.plot(
    df[!, :r], df[!, :g], df[!, :b],
    color=df[!, :kind],
    seriestype=:scatter,
    markersize=1
)


# %%
df_lab = DataFrame(r=[], g=[], b=[], kind=[])
for i in 1:model_config.n_bg+1
    color = @sprintf("#%02x%02x%02x", bmat[i, 1], bmat[i, 2], bmat[i, 3]);
    v = toCIELAB(bmat[i, 1] / 255, bmat[i, 2] / 255, bmat[i, 3] / 255)
    push!(df_lab, [v[1], v[2], v[3], color])
end
for i in 1:model_config.n_fg+1
    color = @sprintf("#%02x%02x%02x", fmat[i, 1], fmat[i, 2], fmat[i, 3]);
    v = toCIELAB(fmat[i, 1] / 255, fmat[i, 2] / 255, fmat[i, 3] / 255)
    push!(df_lab, [v[1], v[2], v[3], color])
end

Plots.plot(
    df_lab[!, :r], df_lab[!, :g], df_lab[!, :b],
    color=df_lab[!, :kind],
    seriestype=:scatter,
    markersize=1
)

