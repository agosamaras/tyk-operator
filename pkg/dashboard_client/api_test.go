package dashboard_client

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/TykTechnologies/tyk-operator/api/v1alpha1"
	"github.com/TykTechnologies/tyk-operator/pkg/environmet"
	"github.com/TykTechnologies/tyk-operator/pkg/universal_client"
)

const contentJSON = "application/json"

const testAPIID = "ZGVmYXVsdC9odHRwYmlu"

func TestAPI(t *testing.T) {
	var e environmet.Env
	e.Parse()
	h := mockDash(t,
		&route{
			path:   "/api/apis",
			method: http.MethodPost,
			body:   "api.Create.body",
		},
		&route{
			path:   "/api/apis",
			method: http.MethodGet,
			body:   "api.All.body",
		},
		&route{
			path:   "/api/apis/5fd08ed769710900018bc196",
			method: http.MethodGet,
			body:   "api.Get.body",
		},
		&route{
			path:   "/api/apis/5fd08ed769710900018bc196",
			method: http.MethodPut,
			body:   "api.Update.body",
		},
		&route{
			path:   "/api/apis/5fd08ed769710900018bc196",
			method: http.MethodDelete,
			body:   "api.Delete.body",
		},
	)
	svr := httptest.NewServer(h)
	defer svr.Close()
	e.URL = svr.URL
	e = env().Merge(e)
	requestAPI(t, e, "Create",
		Kase{
			Name: "Create",
			Request: RequestKase{
				Path:   "/api/apis",
				Method: http.MethodPost,
				Headers: map[string]string{
					XAuthorization: e.Auth,
					XContentType:   contentJSON,
				},
			},
			Response: &ResponseKase{
				Body: ReadSample(t, "api.Create.body"),
			},
		},
		Kase{
			Name: "Get",
			Request: RequestKase{
				Path:   "/api/apis/5fd08ed769710900018bc196",
				Method: http.MethodGet,
				Headers: map[string]string{
					XAuthorization: e.Auth,
					XContentType:   contentJSON,
				},
			},
			Response: &ResponseKase{
				Body: ReadSample(t, "api.Get.body"),
			},
		},
		Kase{
			Name: "Update",
			Request: RequestKase{
				Path:   "/api/apis/5fd08ed769710900018bc196",
				Method: http.MethodPut,
				Headers: map[string]string{
					XAuthorization: e.Auth,
					XContentType:   contentJSON,
				},
			},
			Response: &ResponseKase{
				Body: ReadSample(t, "api.Update.body"),
			},
		},
	)

	requestAPI(t, e, "All", Kase{
		Name: "All",
		Request: RequestKase{
			Path:   "/api/apis",
			Method: http.MethodGet,
			Headers: map[string]string{
				XAuthorization: e.Auth,
				XContentType:   contentJSON,
			},
		},
		Response: &ResponseKase{
			Body: ReadSample(t, "api.All.body"),
		},
	})

	requestAPI(t, e, "Get",
		Kase{
			Name: "All",
			Request: RequestKase{
				Path:   "/api/apis",
				Method: http.MethodGet,
				Headers: map[string]string{
					XAuthorization: e.Auth,
					XContentType:   contentJSON,
				},
			},
			Response: &ResponseKase{
				Body: ReadSample(t, "api.All.body"),
			},
		},
	)

	requestAPI(t, e, "Update",
		Kase{
			Name: "All",
			Request: RequestKase{
				Path:   "/api/apis",
				Method: http.MethodGet,
				Headers: map[string]string{
					XAuthorization: e.Auth,
					XContentType:   contentJSON,
				},
			},
			Response: &ResponseKase{
				Body: ReadSample(t, "api.All.body"),
			},
		},
		Kase{
			Name: "Update",
			Request: RequestKase{
				Path:   "/api/apis/5fd08ed769710900018bc196",
				Method: http.MethodPut,
				Headers: map[string]string{
					XAuthorization: e.Auth,
					XContentType:   contentJSON,
				},
			},
			Response: &ResponseKase{
				Body: ReadSample(t, "api.Update.body"),
			},
		})

	requestAPI(t, e, "Delete",
		Kase{
			Name: "All",
			Request: RequestKase{
				Path:   "/api/apis",
				Method: http.MethodGet,
				Headers: map[string]string{
					XAuthorization: e.Auth,
					XContentType:   contentJSON,
				},
			},
			Response: &ResponseKase{
				Body: ReadSample(t, "api.All.body"),
			},
		},
		Kase{
			Name: "Delete",
			Request: RequestKase{
				Path:   "/api/apis/5fd08ed769710900018bc196",
				Method: http.MethodDelete,
				Headers: map[string]string{
					XAuthorization: e.Auth,
					XContentType:   contentJSON,
				},
			},
			Response: &ResponseKase{
				Body: ReadSample(t, "api.Delete.body"),
			},
		})

}

func requestAPI(t *testing.T, e environmet.Env, name string, kase ...universal_client.Kase) {
	t.Helper()

	t.Run(name, func(t *testing.T) {
		switch name {
		case "All":
			universal_client.RunRequestKase(t, e,
				func(c universal_client.Client) error {
					newKlient(c).Api().All()
					return nil
				},
				kase...,
			)
		case "Get":
			universal_client.RunRequestKase(t, e,
				func(c universal_client.Client) error {
					newKlient(c).Api().Get(testAPIID)
					return nil
				},
				kase...,
			)
		case "Update":
			universal_client.RunRequestKase(t, e,
				func(c universal_client.Client) error {
					var s v1alpha1.APIDefinitionSpec
					Sample(t, "api."+name, &s)
					newKlient(c).Api().Update(&s)
					return nil
				},
				kase...,
			)
		case "Create":
			universal_client.RunRequestKase(t, e,
				func(c universal_client.Client) error {
					var s v1alpha1.APIDefinitionSpec
					Sample(t, "api."+name, &s)
					newKlient(c).Api().Create(&s)
					return nil
				},
				kase...,
			)
		case "Delete":
			universal_client.RunRequestKase(t, e,
				func(c universal_client.Client) error {
					newKlient(c).Api().Delete(testAPIID)
					return nil
				},
				kase...,
			)
		}
	})
}
