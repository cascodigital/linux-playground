import dash
from dash import dcc, html
from dash.dependencies import Input, Output, State
import plotly.graph_objects as go
import pandas as pd
import yfinance as yf
from datetime import datetime
import dash_bootstrap_components as dbc

app = dash.Dash(__name__, external_stylesheets=[dbc.themes.BOOTSTRAP])

def load_stocks():
    try:
        df = pd.read_csv('acoes.csv')
        print(f"[INFO] CSV carregado: {len(df)} acoes")
        return df
    except Exception as e:
        print(f"[ERRO] ao carregar acoes.csv: {e}")
        return pd.DataFrame(columns=['ticker', 'shares', 'avg_price'])

def get_stock_data(ticker, avg_price):
    try:
        print(f"[INFO] Buscando {ticker}...")
        stock = yf.Ticker(ticker)
        hist = stock.history(period='10d')
        if hist.empty:
            return None
        current_price = hist['Close'].iloc[-1]
        if len(hist) >= 2:
            prev_close = hist['Close'].iloc[-2]
            change_pct_day = ((current_price - prev_close) / prev_close) * 100
            change_value_day = current_price - prev_close
        else:
            change_pct_day = 0
            change_value_day = 0
        if len(hist) >= 8:
            price_7days_ago = hist['Close'].iloc[-8]
            change_pct_7days = ((current_price - price_7days_ago) / price_7days_ago) * 100
            change_value_7days = current_price - price_7days_ago
        elif len(hist) >= 2:
            price_oldest = hist['Close'].iloc[0]
            change_pct_7days = ((current_price - price_oldest) / price_oldest) * 100
            change_value_7days = current_price - price_oldest
        else:
            change_pct_7days = 0
            change_value_7days = 0
        if avg_price > 0:
            change_pct_total = ((current_price - avg_price) / avg_price) * 100
            change_value_total = current_price - avg_price
        else:
            change_pct_total = 0
            change_value_total = 0
        return {
            'ticker': ticker.replace('.SA', ''),
            'price': current_price,
            'avg_price': avg_price,
            'change_pct_day': change_pct_day,
            'change_value_day': change_value_day,
            'change_pct_7days': change_pct_7days,
            'change_value_7days': change_value_7days,
            'change_pct_total': change_pct_total,
            'change_value_total': change_value_total
        }
    except Exception as e:
        print(f"[ERRO] {ticker}: {e}")
        return None

def fetch_stock_data():
    print(f"[INFO] Buscando dados...")
    stocks_df = load_stocks()
    if stocks_df.empty:
        return None
    data_list = []
    for _, row in stocks_df.iterrows():
        stock_data = get_stock_data(row['ticker'], row.get('avg_price', 0))
        if stock_data:
            stock_data['shares'] = row['shares']
            stock_data['value'] = stock_data['price'] * row['shares']
            data_list.append(stock_data)
    if not data_list:
        return None
    df = pd.DataFrame(data_list)
    total_value = df['value'].sum()
    df['participation'] = (df['value'] / total_value) * 100
    df = df.sort_values('value', ascending=False).reset_index(drop=True)
    return df

def create_treemap(df, view_type='day'):
    if df is None or df.empty:
        return go.Figure()
    if view_type == 'day':
        change_pct_col = 'change_pct_day'
        change_value_col = 'change_value_day'
        title_text = 'Variação do Dia'
    elif view_type == '7days':
        change_pct_col = 'change_pct_7days'
        change_value_col = 'change_value_7days'
        title_text = 'Variação dos Últimos 7 Dias'
    else:
        change_pct_col = 'change_pct_total'
        change_value_col = 'change_value_total'
        title_text = 'Ganho/Perda Total'
    labels = []
    for _, row in df.iterrows():
        arrow = "▲" if row[change_pct_col] >= 0 else "▼"
        sign = "+" if row[change_pct_col] >= 0 else ""
        if view_type == 'total':
            label = f"<b style='font-size:16px'>{row['ticker']} {arrow}</b><br><br><span style='font-size:20px'><b>R$ {row['price']:.2f}</b></span><br><span style='font-size:12px; opacity:0.85'>Méd: R$ {row['avg_price']:.2f}</span><br><span style='font-size:14px'>{sign}{row[change_pct_col]:.2f}% | {sign}R$ {row[change_value_col]:.2f}</span><br><span style='font-size:11px; opacity:0.9'>──────────────</span><br><span style='font-size:10px'>Participação: {row['participation']:.2f}%</span>"
        else:
            label = f"<b style='font-size:16px'>{row['ticker']} {arrow}</b><br><br><span style='font-size:20px'><b>R$ {row['price']:.2f}</b></span><br><span style='font-size:14px'>{sign}{row[change_pct_col]:.2f}% | {sign}R$ {row[change_value_col]:.2f}</span><br><span style='font-size:11px; opacity:0.9'>──────────────</span><br><span style='font-size:10px'>Participação: {row['participation']:.2f}%</span>"
        labels.append(label)
    fig = go.Figure(go.Treemap(
        labels=df['ticker'], parents=[''] * len(df), values=df['value'],
        text=labels, textposition='middle center', texttemplate='%{text}',
        textfont=dict(size=12, color='white', family='Helvetica Neue, Arial'),
        pathbar=dict(visible=False),
        marker=dict(
            colors=df[change_pct_col],
            colorscale=[[0.0,'#c62828'],[0.45,'#e57373'],[0.5,'#78909c'],[0.55,'#66bb6a'],[1.0,'#2e7d32']],
            cmid=0,
            colorbar=dict(title=dict(text="Variação %"),ticksuffix="%",x=1.02,thickness=12,len=0.4),
            line=dict(width=2, color='#263238')
        ),
        hovertemplate='<b>%{label}</b><br>R$ %{customdata[0]:,.2f}<br>%{color:+.2f}%<br>Part: %{customdata[1]:.2f}%<extra></extra>',
        customdata=df[['price','participation']].values
    ))
    fig.update_layout(
        title=dict(text=f'<b>{title_text}</b>',x=0.5,xanchor='center',font=dict(size=22,color='#000')),
        margin=dict(t=60,l=10,r=100,b=10), height=850, paper_bgcolor='#fafafa'
    )
    return fig

app.layout = dbc.Container([
    html.H1('Mapa de Ações', className='text-center mb-1'),
    html.Div([
        html.P(id='time', className='text-center text-muted', style={'display':'inline-block','margin-right':'15px','margin-bottom':'0'}),
        html.P(id='countdown', className='text-center', style={'display':'inline-block','font-size':'14px','color':'#2e7d32','font-weight':'bold','margin-bottom':'0'})
    ], style={'text-align':'center','margin-bottom':'15px'}),
    dcc.Graph(id='treemap'),
    dcc.Store(id='data'), dcc.Store(id='view', data=0),
    dcc.Interval(id='rotate', interval=5000, n_intervals=0),
    dcc.Interval(id='fetch', interval=300000, n_intervals=0),
    dcc.Interval(id='countdown-timer', interval=1000, n_intervals=0)
], fluid=True, style={'padding':'30px','background-color':'#fafafa'})

@app.callback([Output('data','data'),Output('time','children')],Input('fetch','n_intervals'))
def update_data(n):
    df = fetch_stock_data()
    if df is not None:
        return df.to_dict('records'), f"Atualizado em {datetime.now().strftime('%d/%m/%Y às %H:%M:%S')}"
    return None, "Erro"

@app.callback(Output('view','data'),Input('rotate','n_intervals'),State('view','data'))
def rotate(n,c):
    rotation_map = [0, 0, 0, 0, 1, 1, 2, 2]
    index = n % len(rotation_map)
    return rotation_map[index]

@app.callback(Output('countdown','children'),Input('countdown-timer','n_intervals'))
def update_countdown(n):
    rotation_map = [0, 0, 0, 0, 1, 1, 2, 2]
    total_cycle = len(rotation_map) * 5  # 40 segundos total
    seconds_in_cycle = n % total_cycle
    
    # Calcular posição atual e tempo restante
    position = seconds_in_cycle // 5  # Qual bloco de 5s estamos
    seconds_in_block = seconds_in_cycle % 5  # Quantos segundos dentro do bloco
    
    if position < 4:  # View 0 (dia) - 20 segundos
        remaining = 20 - seconds_in_cycle
    elif position < 6:  # View 1 (7 dias) - 10 segundos
        remaining = 30 - seconds_in_cycle
    else:  # View 2 (total) - 10 segundos
        remaining = 40 - seconds_in_cycle
    
    return f"⏱ {remaining}s"

@app.callback(Output('treemap','figure'),[Input('data','data'),Input('view','data')])
def update_display(data,view_idx):
    if data is None:
        return go.Figure()
    df = pd.DataFrame(data)
    views = ['day','7days','total']
    return create_treemap(df, views[view_idx] if view_idx is not None else 'day')

if __name__ == '__main__':
    app.run_server(host='0.0.0.0', port=8050, debug=True)

