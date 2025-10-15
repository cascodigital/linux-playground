import dash
from dash import dcc, html, dash_table
from dash.dependencies import Input, Output, State
from dash import callback_context
import plotly.graph_objects as go
import pandas as pd
import yfinance as yf
from datetime import datetime
import dash_bootstrap_components as dbc

app = dash.Dash(__name__, external_stylesheets=[dbc.themes.BOOTSTRAP], suppress_callback_exceptions=True)

def load_stocks():
    try:
        df = pd.read_csv('acoes.csv')
        print(f"[INFO] CSV carregado: {len(df)} acoes")
        return df
    except Exception as e:
        print(f"[ERRO] ao carregar acoes.csv: {e}")
        return pd.DataFrame(columns=['ticker', 'shares', 'avg_price'])

def save_stocks(df):
    try:
        df.to_csv('acoes.csv', index=False)
        print(f"[INFO] CSV salvo com {len(df)} acoes")
        return True
    except Exception as e:
        print(f"[ERRO] ao salvar acoes.csv: {e}")
        return False

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
        title_text = 'Variacao do Dia'
    elif view_type == '7days':
        change_pct_col = 'change_pct_7days'
        change_value_col = 'change_value_7days'
        title_text = 'Variacao dos Ultimos 7 Dias'
    else:
        change_pct_col = 'change_pct_total'
        change_value_col = 'change_value_total'
        title_text = 'Ganho/Perda Total'
    labels = []
    for _, row in df.iterrows():
        arrow = "▲" if row[change_pct_col] >= 0 else "▼"
        sign = "+" if row[change_pct_col] >= 0 else ""
        if view_type == 'total':
            label = f"<b style='font-size:16px'>{row['ticker']} {arrow}</b><br><br><span style='font-size:20px'><b>R$ {row['price']:.2f}</b></span><br><span style='font-size:12px; opacity:0.85'>Med: R$ {row['avg_price']:.2f}</span><br><span style='font-size:14px'>{sign}{row[change_pct_col]:.2f}%</span><br><span style='font-size:12px'>({sign}R$ {row[change_value_col]:.2f})</span>"
        else:
            label = f"<b style='font-size:16px'>{row['ticker']} {arrow}</b><br><br><span style='font-size:20px'><b>R$ {row['price']:.2f}</b></span><br><span style='font-size:14px'>{sign}{row[change_pct_col]:.2f}%</span><br><span style='font-size:12px'>({sign}R$ {row[change_value_col]:.2f})</span>"
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
            colorbar=dict(title=dict(text="Variacao %"),ticksuffix="%",x=1.02,thickness=12,len=0.4),
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

app.layout = html.Div([
    dcc.Location(id='url', refresh=False),
    html.Div(id='page-content')
])

# Layout da pagina principal
def main_layout():
    return dbc.Container([
        html.Div([
            html.H1('Mapa de Acoes', className='text-center mb-1', style={'display':'inline-block'}),
            html.A(html.Button('⚙', style={
                'position':'absolute','right':'30px','top':'30px','border':'none',
                'background':'#2e7d32','color':'white','border-radius':'50%',
                'width':'40px','height':'40px','font-size':'20px','cursor':'pointer',
                'box-shadow':'0 2px 5px rgba(0,0,0,0.2)','transition':'all 0.3s'
            }, className='settings-btn'), href='/editar')
        ], style={'position':'relative'}),
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

# Layout da pagina de edicao
def edit_layout():
    stocks_df = load_stocks()
    return dbc.Container([
        html.H2('Gerenciar Acoes', className='text-center mb-4', style={'color':'#2e7d32'}),
        html.A(html.Button('← Voltar', style={
            'margin-bottom':'20px','background':'#78909c','color':'white',
            'border':'none','padding':'10px 20px','border-radius':'5px',
            'cursor':'pointer','font-size':'14px'
        }), href='/'),

        dbc.Card([
            dbc.CardBody([
                html.H4('Adicionar Nova Acao', className='mb-3'),
                dbc.Row([
                    dbc.Col([
                        dbc.Label('Ticker (ex: PETR4)'),
                        dbc.Input(id='input-ticker', type='text', placeholder='PETR4')
                    ], width=4),
                    dbc.Col([
                        dbc.Label('Quantidade'),
                        dbc.Input(id='input-shares', type='number', placeholder='100')
                    ], width=4),
                    dbc.Col([
                        dbc.Label('Preco Medio'),
                        dbc.Input(id='input-price', type='text', placeholder='10.50')
                    ], width=4)
                ]),
                html.Button('Adicionar', id='btn-add', n_clicks=0, style={
                    'margin-top':'15px','background':'#2e7d32','color':'white',
                    'border':'none','padding':'10px 30px','border-radius':'5px',
                    'cursor':'pointer','font-weight':'bold'
                }),
                html.Div(id='add-message', style={'margin-top':'10px','font-weight':'bold'})
            ])
        ], className='mb-4'),

        dbc.Card([
            dbc.CardBody([
                html.H4('Acoes Cadastradas', className='mb-3'),
                html.Div(id='stocks-table'),
                html.Div(id='delete-message', style={'margin-top':'10px','font-weight':'bold'}),
                dcc.Store(id='update-trigger', data=0),
                html.Div(id='delete-trigger', style={'display':'none'})
            ])
        ])
    ], fluid=True, style={'padding':'30px','background-color':'#fafafa','max-width':'1200px'})

@app.callback(Output('page-content','children'), Input('url','pathname'))
def display_page(pathname):
    if pathname == '/editar':
        return edit_layout()
    return main_layout()

@app.callback([Output('data','data'),Output('time','children')],Input('fetch','n_intervals'))
def update_data(n):
    df = fetch_stock_data()
    if df is not None:
        return df.to_dict('records'), f"Atualizado em {datetime.now().strftime('%d/%m/%Y as %H:%M:%S')}"
    return None, "Erro"

@app.callback(Output('view','data'),Input('rotate','n_intervals'),State('view','data'))
def rotate(n,c):
    rotation_map = [0, 0, 0, 0, 1, 1, 2, 2]
    index = n % len(rotation_map)
    return rotation_map[index]

@app.callback(Output('countdown','children'),Input('countdown-timer','n_intervals'))
def update_countdown(n):
    rotation_map = [0, 0, 0, 0, 1, 1, 2, 2]
    total_cycle = len(rotation_map) * 5
    seconds_in_cycle = n % total_cycle
    position = seconds_in_cycle // 5
    if position < 4:
        remaining = 20 - seconds_in_cycle
    elif position < 6:
        remaining = 30 - seconds_in_cycle
    else:
        remaining = 40 - seconds_in_cycle
    return f"⏱ {remaining}s"

@app.callback(Output('treemap','figure'),[Input('data','data'),Input('view','data')])
def update_display(data,view_idx):
    if data is None:
        return go.Figure()
    df = pd.DataFrame(data)
    views = ['day','7days','total']
    return create_treemap(df, views[view_idx] if view_idx is not None else 'day')

@app.callback(
    [Output('add-message','children'), Output('add-message','style'),
     Output('input-ticker','value'), Output('input-shares','value'), 
     Output('input-price','value'), Output('update-trigger','data')],
    Input('btn-add','n_clicks'),
    [State('input-ticker','value'), State('input-shares','value'), 
     State('input-price','value'), State('update-trigger','data')]
)
def add_stock(n_clicks, ticker, shares, price, trigger):
    if n_clicks == 0:
        return '', {}, '', '', '', trigger

    if not ticker or not shares or not price:
        return 'Preencha todos os campos!', {'color':'#c62828','margin-top':'10px','font-weight':'bold'}, ticker, shares, price, trigger

    try:
        ticker = ticker.upper().strip()
        if not ticker.endswith('.SA'):
            ticker = f'{ticker}.SA'

        price = str(price).replace(',', '.')
        price_float = float(price)
        shares_int = int(shares)

        df = load_stocks()

        if ticker in df['ticker'].values:
            return f'{ticker} ja cadastrado!', {'color':'#c62828','margin-top':'10px','font-weight':'bold'}, ticker, shares, price, trigger

        new_row = pd.DataFrame([{'ticker': ticker, 'shares': shares_int, 'avg_price': price_float}])
        df = pd.concat([df, new_row], ignore_index=True)

        if save_stocks(df):
            return f'{ticker} adicionado com sucesso!', {'color':'#2e7d32','margin-top':'10px','font-weight':'bold'}, '', '', '', trigger + 1
        else:
            return 'Erro ao salvar!', {'color':'#c62828','margin-top':'10px','font-weight':'bold'}, ticker, shares, price, trigger

    except Exception as e:
        return f'Erro: {str(e)}', {'color':'#c62828','margin-top':'10px','font-weight':'bold'}, ticker, shares, price, trigger

@app.callback(
    [Output('stocks-table','children'), Output('delete-message','children')],
    [Input('update-trigger','data'), Input('url','pathname'), Input('delete-trigger','children')]
)
def update_table(trigger, pathname, delete_trigger):
    df = load_stocks()

    if df.empty:
        return html.P('Nenhuma acao cadastrada.', style={'color':'#78909c','font-style':'italic'}), ''

    table_rows = []
    for idx, row in df.iterrows():
        table_rows.append(
            html.Tr([
                html.Td(row['ticker'], style={'padding':'10px','border-bottom':'1px solid #ddd'}),
                html.Td(f"{row['shares']}", style={'padding':'10px','border-bottom':'1px solid #ddd','text-align':'center'}),
                html.Td(f"R$ {row['avg_price']:.2f}", style={'padding':'10px','border-bottom':'1px solid #ddd','text-align':'right'}),
                html.Td(
                    html.Button('🗑', id={'type':'delete-btn','index':idx}, n_clicks=0, style={
                        'background':'#c62828','color':'white','border':'none',
                        'padding':'5px 12px','border-radius':'3px','cursor':'pointer',
                        'font-size':'16px'
                    }),
                    style={'padding':'10px','border-bottom':'1px solid #ddd','text-align':'center'}
                )
            ])
        )

    table = html.Table([
        html.Thead(html.Tr([
            html.Th('Ticker', style={'padding':'10px','border-bottom':'2px solid #2e7d32','text-align':'left'}),
            html.Th('Quantidade', style={'padding':'10px','border-bottom':'2px solid #2e7d32','text-align':'center'}),
            html.Th('Preco Medio', style={'padding':'10px','border-bottom':'2px solid #2e7d32','text-align':'right'}),
            html.Th('Acao', style={'padding':'10px','border-bottom':'2px solid #2e7d32','text-align':'center'})
        ])),
        html.Tbody(table_rows)
    ], style={'width':'100%','border-collapse':'collapse'})

    return table, ''

@app.callback(
    Output('delete-trigger','children'),
    Input({'type':'delete-btn','index':dash.dependencies.ALL},'n_clicks'),
    prevent_initial_call=True
)
def delete_stock(n_clicks_list):
    ctx = callback_context

    if not ctx.triggered or not any(n_clicks_list):
        return ''

    button_id = ctx.triggered[0]['prop_id'].split('.')[0]

    try:
        import json
        button_dict = json.loads(button_id)
        row_idx = button_dict['index']

        df = load_stocks()
        if row_idx < len(df):
            ticker = df.iloc[row_idx]['ticker']
            df = df.drop(row_idx).reset_index(drop=True)
            save_stocks(df)
            return f'{ticker} removido'
    except Exception as e:
        print(f"[ERRO] ao deletar: {e}")

    return ''

if __name__ == '__main__':
    app.run_server(host='0.0.0.0', port=8050, debug=True)
